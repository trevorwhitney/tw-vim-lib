package consult

import (
	"context"
	"errors"
	"log/slog"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/workspace"
)

type fakeGH struct{}

func (fakeGH) ListOpenPRs(string) ([]github.PR, error) { return nil, nil }
func (fakeGH) GetPR(repo string, n int) (github.PR, error) {
	return github.PR{Number: n, Title: "bump x", Body: "body", URL: "https://x/pr", HeadSHA: "abc", BaseRef: "main", Author: "renovate[bot]"}, nil
}
func (fakeGH) ChangedFiles(string, int) ([]string, bool, error) { return nil, false, nil }
func (fakeGH) Facts(string, int) (github.Facts, error)          { return github.Facts{}, nil }
func (fakeGH) Diff(string, int) (string, error)                 { return "diff --git a/x b/x\n", nil }
func (fakeGH) Viewer() (string, error)                          { return "twhitney", nil }

// ocFake simulates the consult session behind the opencode.Runner contract:
// onRun receives the runner so it can register a session and deliver a
// report/escalation mid-"session".
type ocFake struct {
	onRun     func(r *Runner, jobID int64, req opencode.Request) (string, error)
	export    string
	exportErr error
	r         *Runner
	reqs      []opencode.Request
}

func (f *ocFake) Run(_ context.Context, req opencode.Request) (string, error) {
	f.reqs = append(f.reqs, req)
	jobID, _ := parseJobID(req.Env["AGENTD_JOB_TOKEN"])
	if f.onRun != nil {
		return f.onRun(f.r, jobID, req)
	}
	return "", nil
}

func (f *ocFake) Export(context.Context, string) (string, error) { return f.export, f.exportErr }

func fixture(t *testing.T, fake *ocFake) (*Runner, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	esc := &escalate.Manager{Store: st, Notify: &notify.Notifier{Banner: "none"},
		RenotifyAfter: 4 * time.Hour, ParkAfter: 24 * time.Hour, Now: time.Now}
	r := New(context.Background(), Deps{
		Store:  st,
		GH:     fakeGH{},
		Esc:    esc,
		WS:     &workspace.Manager{StateDir: t.TempDir(), Exec: execx.Run},
		OC:     fake,
		Log:    slog.Default(),
		Socket: "/tmp/agentd.sock",
	}, 2)
	fake.r = r
	esc.Final = r
	esc.Cont = r
	return r, st
}

func adviceVerdicts() map[string]policy.VerdictAction {
	return map[string]policy.VerdictAction{
		"approve":     {Action: "approve_pr"},
		"needs-human": {Action: "none"},
	}
}

func queuedJob(t *testing.T, st *store.Store) int64 {
	t.Helper()
	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	return id
}

func TestConsultReportAttachesMappedAction(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, _ opencode.Request) (string, error) {
		require.NoError(t, r.RegisterSession(jobID, "ses_1"))
		require.NoError(t, r.Report(jobID, "approve", "looks safe", "detailed analysis"))
		return "done", nil
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x", Verdicts: adviceVerdicts()})
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
	require.Equal(t, "ses_1", job.SessionID)
	require.NotEmpty(t, job.WorktreePath)
	require.Contains(t, job.VerdictsJSON, "approve_pr", "verdict menu persisted on the job")

	esc, ok, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Contains(t, esc.Question, "approve")
	require.Contains(t, esc.Question, "looks safe")
	require.Equal(t, "detailed analysis", esc.Advice)
	// The daemon built the action from job facts; approval executes it.
	require.Equal(t, "approve_pr", esc.ActionKind)
	require.Contains(t, esc.ActionParamsJSON, `"grafana/loki"`)
	require.Contains(t, esc.ActionParamsJSON, `"42"`)

	arts, err := st.ArtifactsForJob(jobID)
	require.NoError(t, err)
	names := map[string]bool{}
	for _, a := range arts {
		names[a.Name] = true
	}
	require.True(t, names["pr.json"] && names["diff.patch"] && names["report.md"])

	// The session ran in the scratch dir, as the consult agent, with the job
	// env, and was told its verdict menu.
	require.Len(t, fake.reqs, 1)
	req := fake.reqs[0]
	require.Equal(t, "consult", req.Agent)
	require.Equal(t, job.WorktreePath, req.Dir)
	require.Equal(t, strconv.FormatInt(jobID, 10), req.Env["AGENTD_JOB_TOKEN"])
	require.Equal(t, "/tmp/agentd.sock", req.Env["AGENTD_SOCKET"])
	require.Contains(t, req.Prompt, "grafana/loki#42")
	require.Contains(t, req.Prompt, "pr.json")
	require.Contains(t, req.Prompt, "approve")
	require.Contains(t, req.Prompt, "needs-human")
}

func TestConsultReportPureAdviceVerdict(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, _ opencode.Request) (string, error) {
		require.NoError(t, r.RegisterSession(jobID, "ses_1"))
		require.NoError(t, r.Report(jobID, "needs-human", "judgment call", "why"))
		return "done", nil
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x", Verdicts: adviceVerdicts()})
	r.Wait()

	esc, ok, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Empty(t, esc.ActionKind, "none-mapped verdict escalates as pure advice")
}

func TestConsultReportRejectsUndeclaredVerdict(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, _ opencode.Request) (string, error) {
		err := r.Report(jobID, "yolo-merge", "s", "d")
		require.Error(t, err, "verdict outside the declared set is rejected")
		require.NoError(t, r.Report(jobID, "needs-human", "s", "d"))
		return "done", nil
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x", Verdicts: adviceVerdicts()})
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
}

func TestConsultQuestionPath(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, _ opencode.Request) (string, error) {
		require.NoError(t, r.RegisterSession(jobID, "ses_1"))
		require.NoError(t, r.EscalateQuestion(jobID, "question", "should refactors block?", "context here"))
		return "done", nil
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x"})
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_input", job.State)
}

func TestConsultNoResultRetriesThenEscalates(t *testing.T) {
	fake := &ocFake{onRun: func(_ *Runner, _ int64, _ opencode.Request) (string, error) {
		return "", errors.New("model timeout")
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x"})
	r.Wait()

	require.Len(t, fake.reqs, 2, "one retry")
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_input", job.State)
	esc, ok, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Contains(t, esc.Question, "consult failed")
}

func TestConsultRetryResumesRegisteredSession(t *testing.T) {
	first := true
	fake := &ocFake{onRun: func(r *Runner, jobID int64, req opencode.Request) (string, error) {
		if first {
			first = false
			require.NoError(t, r.RegisterSession(jobID, "ses_1"))
			return "", errors.New("crashed mid-turn")
		}
		require.Equal(t, "ses_1", req.SessionID, "retry resumes the registered session")
		require.NoError(t, r.Report(jobID, "needs-human", "ok", "d"))
		return "done", nil
	}}
	r, st := fixture(t, fake)
	jobID := queuedJob(t, st)

	r.Start(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x", Verdicts: adviceVerdicts()})
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
}

func TestReportOnTerminalJobRejected(t *testing.T) {
	r, st := fixture(t, &ocFake{})
	jobID := queuedJob(t, st)
	require.NoError(t, st.FinishJob(jobID, "done", "acted", "m"))
	require.Error(t, r.Report(jobID, "approve", "s", "d"))
}
