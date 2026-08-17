package engine

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
)

func Test_PollAll_ProcessesConfiguredRepos(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fe := fixture(t, gh, false)

	e.PollAll(context.Background())

	require.Len(t, fe.calls, len(wantApproveAutoMerge))
	statuses := e.Statuses()
	require.Len(t, statuses, 1)
	require.Equal(t, "grafana/loki", statuses[0].Repo)
	require.NotZero(t, statuses[0].LastPollTS)
	require.Empty(t, statuses[0].LastError)
	_ = st
}

func Test_PollAll_PauseSkipsWork(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, _, fe := fixture(t, gh, false)

	e.SetPaused(true)
	e.PollAll(context.Background())
	require.Empty(t, fe.calls)
	require.True(t, e.Paused())
}

func Test_Reconcile_FailsInterruptedQueuedJobs(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, _ := fixture(t, gh, false)

	id, err := st.CreateJob("pr", "grafana/loki", 9, "sha9")
	require.NoError(t, err)

	require.NoError(t, e.Reconcile(context.Background()))

	job, err := st.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "failed", job.State)
	require.Contains(t, job.Error, "interrupted")
}

func Test_EnqueuePR_ProcessesImmediately(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, _, fe := fixture(t, gh, false)

	job, err := e.EnqueuePR(context.Background(), "grafana/loki", 42)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Len(t, fe.calls, len(wantApproveAutoMerge))

	_, err = e.EnqueuePR(context.Background(), "unknown/repo", 1)
	require.Error(t, err)
}

func Test_Retry_RerunsFailedJobWithSameHead(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fe := fixture(t, gh, false)

	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	require.NoError(t, st.FailJob(id, "boom"))

	job, err := e.Retry(context.Background(), id)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
	require.Len(t, fe.calls, len(wantApproveAutoMerge))
}

func Test_Retry_RefusesWhenHeadMoved(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, _ := fixture(t, gh, false)

	id, err := st.CreateJob("pr", "grafana/loki", 42, "old-sha")
	require.NoError(t, err)
	require.NoError(t, st.FailJob(id, "boom"))

	_, err = e.Retry(context.Background(), id)
	require.ErrorContains(t, err, "head moved")
}

func Test_Retry_RefusesWhenNowIneligible(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	gh.facts.CI = github.CIPending
	e, st, _ := fixture(t, gh, false)

	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	require.NoError(t, st.FailJob(id, "boom"))

	_, err = e.Retry(context.Background(), id)
	require.ErrorContains(t, err, "ineligible")

	job, err := st.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "failed", job.State, "refused retry must leave the job untouched")
}

func Test_Once_DryRunWritesLedgerWithoutExecuting(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, fe := fixture(t, gh, false)
	e.Actor.DryRun = true

	require.NoError(t, e.Once(context.Background()))

	job, ok, err := st.JobForHead("grafana/loki", 42, "abc", "pr")
	require.NoError(t, err)
	require.True(t, ok, "dry-run still records the job")
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
	require.Contains(t, job.Summary, "dry-run")
	require.Empty(t, fe.calls, "dry-run must make zero gh calls")
}

func Test_EnqueuePR_ReportsDeferral(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	gh.facts.CI = github.CIPending
	e, _, _ := fixture(t, gh, false)

	_, err := e.EnqueuePR(context.Background(), "grafana/loki", 42)
	require.ErrorContains(t, err, "deferred")
}

func Test_Retry_RefusesNonFailedJobs(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, st, _ := fixture(t, gh, false)
	id, err := st.CreateJob("pr", "grafana/loki", 42, "abc")
	require.NoError(t, err)
	require.NoError(t, st.FinishJob(id, "done", "acted", "merged"))

	_, err = e.Retry(context.Background(), id)
	require.Error(t, err)
}

func Test_PollAll_AuthErrorStopsRepoPolling(t *testing.T) {
	gh := greenGH(renovatePR(), []string{"go.mod"})
	e, _, fe := fixture(t, gh, false)
	e.GH = &authFailGH{}

	e.PollAll(context.Background())
	statuses := e.Statuses()
	require.True(t, statuses[0].AuthError)

	e.PollAll(context.Background())
	require.Empty(t, fe.calls, "auth-failed repo is not polled again")
}

type authFailGH struct{ fakeGH }

func (a *authFailGH) ListOpenPRs(string) ([]github.PR, error) {
	return nil, &github.AuthError{Msg: "HTTP 401: Bad credentials"}
}
