package store

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Actions_IdempotencyKey(t *testing.T) {
	s := openTemp(t)
	jobID, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	act, executed, err := s.UpsertAction(jobID, "merge_pr", `{"number":"1"}`)
	require.NoError(t, err)
	require.False(t, executed)
	require.NotZero(t, act.ID)

	require.NoError(t, s.MarkActionExecuted(act.ID, "merged", false))

	again, executed, err := s.UpsertAction(jobID, "merge_pr", `{"number":"1"}`)
	require.NoError(t, err)
	require.True(t, executed, "already-executed action must be reported as done")
	require.Equal(t, act.ID, again.ID)
	require.Equal(t, "merged", again.Result)

	other, executed, err := s.UpsertAction(jobID, "merge_pr", `{"number":"2"}`)
	require.NoError(t, err)
	require.False(t, executed, "different params are a different action")
	require.NotEqual(t, act.ID, other.ID)
}

func Test_Actions_FailedIsNotExecuted(t *testing.T) {
	s := openTemp(t)
	jobID, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	act, _, err := s.UpsertAction(jobID, "merge_pr", `{}`)
	require.NoError(t, err)
	require.NoError(t, s.MarkActionFailed(act.ID, "gh exploded"))

	_, executed, err := s.UpsertAction(jobID, "merge_pr", `{}`)
	require.NoError(t, err)
	require.False(t, executed, "failed action may be retried")
}

func Test_Decisions_Insert(t *testing.T) {
	s := openTemp(t)
	jobID, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)
	require.NoError(t, s.AddDecision(jobID, "merge-dependency-updates", "act", "all files allowed"))
}

func Test_OpenEscalationForJob_PicksNewest(t *testing.T) {
	st := openTemp(t)
	id, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	_, err = st.CreateEscalation(id, "waiting_input", "first", "", "", "")
	require.NoError(t, err)
	second, err := st.CreateEscalation(id, "waiting_approval", "second", "", "", "")
	require.NoError(t, err)

	esc, ok, err := st.OpenEscalationForJob(id)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, second, esc.ID, "newest open escalation wins")
}

func Test_Escalations_Lifecycle(t *testing.T) {
	s := openTemp(t)
	jobID, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	id, err := s.CreateEscalation(jobID, "waiting_approval",
		"merge outside allowed paths?", "advice", "merge_pr", `{"number":"1"}`)
	require.NoError(t, err)

	open, err := s.OpenEscalations()
	require.NoError(t, err)
	require.Len(t, open, 1)
	require.Equal(t, "merge_pr", open[0].ActionKind)

	n, err := s.CountOpenEscalations()
	require.NoError(t, err)
	require.Equal(t, 1, n)

	esc, ok, err := s.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, id, esc.ID)

	require.NoError(t, s.TouchEscalationNotified(id))

	require.NoError(t, s.ResolveEscalation(id, "reject", "not today", ""))
	got, err := s.GetEscalation(id)
	require.NoError(t, err)
	require.Equal(t, "resolved", got.State)
	require.Equal(t, "reject", got.Resolution)
	require.Equal(t, "not today", got.Reason)

	n, err = s.CountOpenEscalations()
	require.NoError(t, err)
	require.Zero(t, n)
}
