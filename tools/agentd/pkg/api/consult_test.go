package api

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/consult"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/workspace"
)

type fakeOpencode struct{}

func (f *fakeOpencode) Run(context.Context, opencode.Request) (string, error) { return "", nil }
func (f *fakeOpencode) Export(context.Context, string) (string, error)        { return "{}", nil }

var _ opencode.Runner = (*fakeOpencode)(nil)

type fakeTmux struct{}

func (f *fakeTmux) EnsureSession(name string) error { return nil }
func (f *fakeTmux) NewWindow(session, name, dir string, env map[string]string, command string) (string, error) {
	return "@42", nil
}
func (f *fakeTmux) HasWindow(windowID string) (bool, error) { return windowID == "@42", nil }
func (f *fakeTmux) KillWindow(windowID string) error        { return nil }

// shortSocket returns a socket path under /tmp short enough for the macOS
// sun_path limit, which t.TempDir() paths exceed for long test names.
func shortSocket(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "agentd")
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return filepath.Join(dir, "a.sock")
}
func consultFixture(t *testing.T) (*Server, *store.Store, *Client) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	act := &actor.Actor{Store: st, GH: okWriter{}, Sleep: func(time.Duration) {}}
	n := &notify.Notifier{Banner: "none"}
	esc := &escalate.Manager{Store: st, Notify: n, RenotifyAfter: time.Hour, ParkAfter: 24 * time.Hour, Now: time.Now}
	triage, err := policy.NewConsultTriage(nil)
	require.NoError(t, err)

	eng := &engine.Engine{
		Store: st,
		GH:    &fakeGH{pr: github.PR{Number: 42, HeadSHA: "abc", Author: "twhitney"}, files: []string{"go.mod"}},
		Actor: act, Esc: esc,
		Chains: map[string][]policy.WithMeta{"grafana/loki": {{Policy: triage}}},
		Log:    slog.Default(),
	}

	stateDir := t.TempDir()
	fakeExec := func(ctx context.Context, opts execx.Options, name string, args ...string) (string, error) {
		return "", nil
	}
	runner := consult.New(context.Background(), consult.Deps{
		Store:         st,
		GH:            eng.GH,
		Esc:           esc,
		WS:            &workspace.Manager{StateDir: stateDir, Exec: fakeExec},
		Tmux:          &fakeTmux{},
		OC:            &fakeOpencode{},
		Log:           slog.Default(),
		Socket:        "",
		Session:       "test",
		DropinCommand: "echo",
		Locals:        map[string]string{},
	}, 1)

	sock := shortSocket(t)
	srv := &Server{Engine: eng, Esc: esc, Actor: act, Store: st, Consult: runner}
	ln, err := Listen(sock)
	require.NoError(t, err)
	httpSrv := &http.Server{Handler: srv.Handler()}
	go func() { _ = httpSrv.Serve(ln) }()
	t.Cleanup(func() { _ = httpSrv.Close() })

	return srv, st, NewClient(sock)
}

func plainFixture(t *testing.T) (*Server, *store.Store, *Client) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	act := &actor.Actor{Store: st, GH: okWriter{}, Sleep: func(time.Duration) {}}
	n := &notify.Notifier{Banner: "none"}
	esc := &escalate.Manager{Store: st, Notify: n, RenotifyAfter: time.Hour, ParkAfter: 24 * time.Hour, Now: time.Now}
	dep, err := policy.NewDepUpdates(nil)
	require.NoError(t, err)

	eng := &engine.Engine{
		Store: st,
		GH:    &fakeGH{pr: github.PR{Number: 42, HeadSHA: "abc", Author: "renovate[bot]"}, files: []string{"go.mod"}},
		Actor: act, Esc: esc,
		Chains: map[string][]policy.WithMeta{"grafana/loki": {{Policy: dep}}},
		Log:    slog.Default(),
	}

	sock := shortSocket(t)
	srv := &Server{Engine: eng, Esc: esc, Actor: act, Store: st}
	ln, err := Listen(sock)
	require.NoError(t, err)
	httpSrv := &http.Server{Handler: srv.Handler()}
	go func() { _ = httpSrv.Serve(ln) }()
	t.Cleanup(func() { _ = httpSrv.Close() })

	return srv, st, NewClient(sock)
}

func mkQueuedJob(t *testing.T, st *store.Store) int64 {
	t.Helper()
	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	return id
}

func mkWaitingJobWithSession(t *testing.T, st *store.Store) int64 {
	t.Helper()
	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(id, "waiting_approval"))
	require.NoError(t, st.SetJobSessionID(id, "ses_test"))
	require.NoError(t, st.SetJobWorktree(id, "/tmp/wt"))
	_, err = st.CreateEscalation(id, "waiting_approval", "", "", "", "")
	require.NoError(t, err)
	return id
}

func TestSessionEndpoint(t *testing.T) {
	srv, st, c := consultFixture(t)
	jobID := mkQueuedJob(t, st)

	require.NoError(t, c.RegisterSession(jobID, "ses_9"))
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "ses_9", job.SessionID)
	_ = srv
}

func TestReportEndpointCreatesEscalation(t *testing.T) {
	_, st, c := consultFixture(t)
	jobID := mkQueuedJob(t, st)

	require.NoError(t, c.Report(jobID, "approve", "fine", "details"))
	esc, ok, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "waiting_approval", esc.Kind)
}

func TestEscalateEndpoint(t *testing.T) {
	_, st, c := consultFixture(t)
	jobID := mkQueuedJob(t, st)

	require.NoError(t, c.EscalateJob(jobID, "question", "which base?", "ctx"))
	esc, ok, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "waiting_input", esc.Kind)
}

func TestDropinHandbackEndpoints(t *testing.T) {
	_, st, c := consultFixture(t)
	jobID := mkWaitingJobWithSession(t, st)

	require.NoError(t, c.DropIn(jobID))
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "interactive", job.State)

	require.NoError(t, c.Handback(jobID))
	job, err = st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
}

func TestGCEndpoint(t *testing.T) {
	_, _, c := consultFixture(t)
	require.NoError(t, c.GC(0, false), "full sweep")
}

func TestShadowEndpoint(t *testing.T) {
	_, _, c := consultFixture(t)
	require.NoError(t, c.SetShadow("grafana/loki", "consult-triage", true))
	require.Error(t, c.SetShadow("grafana/loki", "missing-policy", true))
}

func TestConsultEndpointsWithoutRunner(t *testing.T) {
	_, _, c := plainFixture(t)
	err := c.Report(1, "v", "s", "d")
	require.Error(t, err)
	require.Contains(t, err.Error(), "503")
}

func TestResolveValidationReturns400(t *testing.T) {
	_, st, c := consultFixture(t)
	jobID, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	escID, err := st.CreateEscalation(jobID, "waiting_approval", "q", "", "", "")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(jobID, "waiting_approval"))

	err = c.Resolve(escID, "reject", "", "")
	require.Error(t, err)
	require.Contains(t, err.Error(), "400", "reject without reason is a caller error")

	err = c.Resolve(escID, "answer", "", "")
	require.Error(t, err)
	require.Contains(t, err.Error(), "400", "answer without text is a caller error")
}

func TestResolveNoContinuerReturns503(t *testing.T) {
	_, st2, c2 := plainFixture(t)
	jobID2, err := st2.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	escID2, err := st2.CreateEscalation(jobID2, "waiting_input", "q", "", "", "")
	require.NoError(t, err)
	require.NoError(t, st2.SetJobState(jobID2, "waiting_input"))

	err = c2.Resolve(escID2, "answer", "", "some text")
	require.Error(t, err)
	require.Contains(t, err.Error(), "503", "missing continuer is service state")
}

func TestReportBadVerdictReturns400(t *testing.T) {
	_, st, c := consultFixture(t)
	jobID, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	verdicts := `{"approve":{"action":"approve_pr"},"needs-human":{"action":"none"}}`
	require.NoError(t, st.SetJobVerdicts(jobID, verdicts))

	err = c.Report(jobID, "yolo-merge", "s", "d")
	require.Error(t, err)
	require.Contains(t, err.Error(), "400", "verdict outside declared set is a caller error")
}
