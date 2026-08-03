package engine

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

type fakeGH struct {
	prs        map[string][]github.PR
	files      map[int][]string
	truncated  bool
	facts      github.Facts
	factsCalls int
}

var _ github.Reader = (*fakeGH)(nil)

func (f *fakeGH) ListOpenPRs(repo string) ([]github.PR, error) { return f.prs[repo], nil }
func (f *fakeGH) GetPR(repo string, n int) (github.PR, error) {
	for _, pr := range f.prs[repo] {
		if pr.Number == n {
			return pr, nil
		}
	}
	return github.PR{}, errors.New("pr not found")
}
func (f *fakeGH) ChangedFiles(_ string, n int) ([]string, bool, error) {
	return f.files[n], f.truncated, nil
}
func (f *fakeGH) Facts(string, int) (github.Facts, error) {
	f.factsCalls++
	return f.facts, nil
}
func (f *fakeGH) Viewer() (string, error) { return "twhitney", nil }

// fakeWriter satisfies github.Writer and records writes as one line each, so
// tests can assert exact write activity.
type fakeWriter struct{ calls []string }

var _ github.Writer = (*fakeWriter)(nil)

func (f *fakeWriter) MergePR(_ context.Context, repo string, n int, method string) (string, error) {
	f.calls = append(f.calls, fmt.Sprintf("merge %s#%d --%s", repo, n, method))
	return "merged", nil
}

func (f *fakeWriter) ApprovePR(_ context.Context, repo string, n int) (string, error) {
	f.calls = append(f.calls, fmt.Sprintf("approve %s#%d", repo, n))
	return "approved", nil
}

func (f *fakeWriter) CommentPR(_ context.Context, repo string, n int, _ string) (string, error) {
	f.calls = append(f.calls, fmt.Sprintf("comment %s#%d", repo, n))
	return "commented", nil
}

func fixture(t *testing.T, gh *fakeGH, shadow bool) (*Engine, *store.Store, *fakeWriter) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	fe := &fakeWriter{}
	act := &actor.Actor{Store: st, GH: fe, Sleep: func(time.Duration) {}}
	n := &notify.Notifier{Banner: "none"}
	esc := &escalate.Manager{Store: st, Notify: n,
		RenotifyAfter: 4 * time.Hour, ParkAfter: 24 * time.Hour, Now: time.Now}

	dep, err := policy.NewDepUpdates(nil)
	require.NoError(t, err)
	e := &Engine{
		Store: st, GH: gh, Actor: act, Esc: esc,
		Chains: map[string][]policy.WithMeta{
			"grafana/loki": {{Policy: dep, Shadow: shadow}},
		},
		Log: slog.Default(),
	}
	return e, st, fe
}

func renovatePR() github.PR {
	return github.PR{Number: 42, Title: "bump x", HeadSHA: "abc", Author: "renovate[bot]"}
}

func greenGH(pr github.PR, files []string) *fakeGH {
	return &fakeGH{
		prs:   map[string][]github.PR{"grafana/loki": {pr}},
		files: map[int][]string{pr.Number: files},
		facts: github.Facts{CI: github.CISuccess, Mergeable: github.MergeClean},
	}
}

func Test_ProcessPR_MergesRenovateLockfileOnly(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod", "go.sum"})
	e, st, fe := fixture(t, gh, false)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))

	job, ok, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
	require.Equal(t, []string{"merge grafana/loki#42 --squash"}, fe.calls)
}

func Test_ProcessPR_SameHeadIsSkippedOnce(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fe := fixture(t, gh, false)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))
	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))

	require.Len(t, fe.calls, 1, "second pass over same head must be a no-op")
	_ = st
}

func Test_ProcessPR_IneligibleLeavesNoRecord(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	gh.facts.CI = github.CIPending
	e, st, fe := fixture(t, gh, false)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))

	seen, err := st.HasJob("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.False(t, seen, "deferred PR must leave no job so a later poll retries")
	require.Empty(t, fe.calls)
	require.Equal(t, 1, gh.factsCalls)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))
	require.Equal(t, 1, gh.factsCalls, "deferred head is not re-fact-checked within the backoff window")

	gh.facts.CI = github.CISuccess
	e.deferredAt["grafana/loki#42@abc"] = time.Now().Add(-10 * time.Minute)
	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))
	require.Len(t, fe.calls, 1, "same head processes once CI goes green and the backoff expires")
}

func Test_ProcessPR_OutsideFilesEscalates(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod", "main.go"})
	e, st, fe := fixture(t, gh, false)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))

	job, _, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
	require.Empty(t, fe.calls, "no gh call without approval")

	esc, ok, err := st.OpenEscalationForJob(job.ID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "merge_pr", esc.ActionKind)
}

func Test_ProcessPR_NonBotSkips(t *testing.T) {
	pr := github.PR{Number: 7, HeadSHA: "s7", Author: "alice"}
	gh := greenGH(pr, []string{"main.go"})
	e, st, fe := fixture(t, gh, false)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", pr, e.Chains["grafana/loki"]))

	job, _, err := st.JobForHead("grafana/loki", 7, "s7", "pr")
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "skipped", job.Outcome)
	require.Empty(t, fe.calls)
}

func Test_ProcessPR_ShadowRecordsWithoutExecuting(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fe := fixture(t, gh, true)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), e.Chains["grafana/loki"]))

	job, _, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
	require.Contains(t, job.Summary, "shadow")
	require.Empty(t, fe.calls, "shadow must not execute gh")
}
