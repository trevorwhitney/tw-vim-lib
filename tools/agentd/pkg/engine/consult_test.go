package engine

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/consult"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
)

type fakeConsult struct {
	started []consult.Request
	calls   []string
}

func (f *fakeConsult) Start(req consult.Request) { f.started = append(f.started, req) }
func (f *fakeConsult) Wait()                     { f.calls = append(f.calls, "wait") }
func (f *fakeConsult) SweepInteractive() error   { f.calls = append(f.calls, "sweep"); return nil }
func (f *fakeConsult) Reconcile(onRestart string) error {
	f.calls = append(f.calls, "reconcile:"+onRestart)
	return nil
}

func triageChain(t *testing.T) []policy.WithMeta {
	t.Helper()
	p, err := policy.NewConsultTriage(nil)
	require.NoError(t, err)
	return []policy.WithMeta{{Policy: p}}
}

func TestConsultVerdictStartsRunner(t *testing.T) {
	pr := renovatePR()
	gh := greenGH(pr, []string{"go.mod"})
	e, st, _ := fixture(t, gh, false)
	fc := &fakeConsult{}
	e.Consult = fc
	e.Chains["grafana/loki"] = triageChain(t)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", pr, e.Chains["grafana/loki"]))

	job, ok, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "preparing", job.State)
	require.Len(t, fc.started, 1)
	req := fc.started[0]
	require.Equal(t, job.ID, req.JobID)
	require.Equal(t, "grafana/loki", req.Repo)
	require.Equal(t, 42, req.Number)
	require.Contains(t, req.Verdicts, "needs-human", "policy's verdict menu travels with the request")
}

func TestConsultVerdictWithoutRunnerFails(t *testing.T) {
	pr := renovatePR()
	gh := greenGH(pr, []string{"go.mod"})
	e, st, _ := fixture(t, gh, false)
	e.Chains["grafana/loki"] = triageChain(t)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", pr, e.Chains["grafana/loki"]))

	job, _, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.Equal(t, "failed", job.State)
}

func TestOnceWaitsAndReconcileDelegates(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, _, _ := fixture(t, gh, false)
	fc := &fakeConsult{}
	e.Consult = fc
	e.OnRestart = "resume"

	require.NoError(t, e.Once(context.Background()))

	require.Contains(t, fc.calls, "reconcile:resume")
	require.Contains(t, fc.calls, "sweep")
	require.Equal(t, "wait", fc.calls[len(fc.calls)-1], "Once waits for consults last")
}

func TestSetShadow(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fw := fixture(t, gh, false)

	require.NoError(t, e.SetShadow("grafana/loki", "merge-dependency-updates", true))
	require.Error(t, e.SetShadow("grafana/loki", "nope", true))
	require.Error(t, e.SetShadow("a/b", "merge-dependency-updates", true))

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", renovatePR(), nil))

	job, _, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.Contains(t, job.Summary, "shadow")
	require.Empty(t, fw.calls)
	_ = fmt.Sprint()
}

func TestEnqueueBypassesDeferBackoff(t *testing.T) {
	pr := renovatePR()
	gh := greenGH(pr, []string{"go.mod"})
	gh.facts = github.Facts{CI: github.CIPending, Mergeable: github.MergeClean}
	e, st, _ := fixture(t, gh, false)
	fc := &fakeConsult{}
	e.Consult = fc
	e.Chains["grafana/loki"] = triageChain(t)

	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", pr, nil))
	_, ok, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.False(t, ok, "pending CI defers without a job")

	gh.facts = github.Facts{CI: github.CISuccess, Mergeable: github.MergeClean}
	require.NoError(t, e.ProcessPR(context.Background(), "grafana/loki", pr, nil))
	_, ok, err = st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.False(t, ok, "poller re-evaluation stays suppressed by the backoff")

	job, err := e.EnqueuePR(context.Background(), "grafana/loki", 42)
	require.NoError(t, err, "explicit enqueue bypasses the backoff")
	require.Equal(t, "preparing", job.State)
}
