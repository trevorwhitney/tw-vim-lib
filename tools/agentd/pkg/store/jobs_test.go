package store

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Jobs_CreateHasGet(t *testing.T) {
	s := openTemp(t)

	seen, err := s.HasJob("grafana/loki", 42, "abc123", "pr")
	require.NoError(t, err)
	require.False(t, seen)

	id, err := s.CreateJob("pr", "grafana/loki", 42, "abc123")
	require.NoError(t, err)

	seen, err = s.HasJob("grafana/loki", 42, "abc123", "pr")
	require.NoError(t, err)
	require.True(t, seen)

	job, err := s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "queued", job.State)
	require.Equal(t, "grafana/loki", job.Repo)
	require.Equal(t, 42, job.PRNumber)
	require.Equal(t, "abc123", job.HeadSHA)

	_, err = s.CreateJob("pr", "grafana/loki", 42, "abc123")
	require.Error(t, err, "duplicate idempotency key must be rejected")
}

func Test_ClaimJobState(t *testing.T) {
	st := openTemp(t)
	id, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)

	won, err := st.ClaimJobState(id, "running", "queued", "preparing")
	require.NoError(t, err)
	require.True(t, won)
	job, err := st.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "running", job.State)

	won, err = st.ClaimJobState(id, "waiting_input", "queued", "preparing")
	require.NoError(t, err)
	require.False(t, won, "claim from a state the job already left must lose")
	job, err = st.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "running", job.State, "a lost claim must not change state")
}

func Test_Jobs_Transitions(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	require.NoError(t, s.SetJobState(id, "waiting_approval"))
	job, err := s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
	require.Zero(t, job.FinishedTS)

	require.NoError(t, s.FinishJob(id, "done", "acted", "merged"))
	job, err = s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
	require.Equal(t, "merged", job.Summary)
	require.NotZero(t, job.FinishedTS)
}

func Test_Jobs_FailResetAndQuery(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	require.NoError(t, s.FailJob(id, "boom"))
	job, err := s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "failed", job.State)
	require.Equal(t, "boom", job.Error)

	failed, err := s.JobsInState("failed")
	require.NoError(t, err)
	require.Len(t, failed, 1)

	require.NoError(t, s.ResetJob(id))
	job, err = s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "queued", job.State)
	require.Empty(t, job.Error)
	require.Zero(t, job.FinishedTS)

	require.NoError(t, s.AddEvent(id, "retried", `{"by":"cli"}`))
}

func Test_Jobs_JobForHead(t *testing.T) {
	s := openTemp(t)
	_, err := s.CreateJob("pr", "a/b", 7, "sha7")
	require.NoError(t, err)

	job, ok, err := s.JobForHead("a/b", 7, "sha7", "pr")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, 7, job.PRNumber)

	_, ok, err = s.JobForHead("a/b", 7, "other", "pr")
	require.NoError(t, err)
	require.False(t, ok)
}
