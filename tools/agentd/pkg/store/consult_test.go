package store

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestJobConsultColumns(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)

	require.NoError(t, s.SetJobSessionID(id, "ses_123"))
	require.NoError(t, s.SetJobWorktree(id, "/tmp/wt"))
	require.NoError(t, s.SetJobWindowID(id, "@7"))
	require.NoError(t, s.SetJobVerdicts(id, `{"approve":{"action":"none"}}`))

	job, err := s.GetJob(id)
	require.NoError(t, err)
	require.Equal(t, "ses_123", job.SessionID)
	require.Equal(t, "/tmp/wt", job.WorktreePath)
	require.Equal(t, "@7", job.WindowID)
	require.Equal(t, `{"approve":{"action":"none"}}`, job.VerdictsJSON)
}

func TestNonTerminalJobs(t *testing.T) {
	s := openTemp(t)
	a, err := s.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	b, err := s.CreateJob("pr", "a/b", 2, "s2")
	require.NoError(t, err)
	c, err := s.CreateJob("pr", "a/b", 3, "s3")
	require.NoError(t, err)

	require.NoError(t, s.SetJobState(a, "running"))
	require.NoError(t, s.FinishJob(b, "done", "acted", "merged"))
	require.NoError(t, s.FailJob(c, "boom"))

	jobs, err := s.NonTerminalJobs()
	require.NoError(t, err)
	require.Len(t, jobs, 1)
	require.Equal(t, a, jobs[0].ID)
}

func TestEventQueries(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)

	has, err := s.HasEvent(id, "dropin")
	require.NoError(t, err)
	require.False(t, has)

	require.NoError(t, s.AddEvent(id, "dropin", ""))
	require.NoError(t, s.AddEvent(id, "finalizing", `{"state":"done"}`))
	require.NoError(t, s.AddEvent(id, "finalizing", `{"state":"rejected"}`))

	has, err = s.HasEvent(id, "dropin")
	require.NoError(t, err)
	require.True(t, has)

	payload, ok, err := s.LatestEventPayload(id, "finalizing")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, `{"state":"rejected"}`, payload)

	_, ok, err = s.LatestEventPayload(id, "nonexistent")
	require.NoError(t, err)
	require.False(t, ok)
}

func TestArtifacts(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)

	require.NoError(t, s.AddArtifact(id, "diff.patch", "/state/jobs/1/diff.patch"))
	require.NoError(t, s.AddArtifact(id, "report.md", "/state/jobs/1/report.md"))

	arts, err := s.ArtifactsForJob(id)
	require.NoError(t, err)
	require.Len(t, arts, 2)
	require.Equal(t, "diff.patch", arts[0].Name)
}

func TestResolveEscalationStoresAnswer(t *testing.T) {
	s := openTemp(t)
	id, err := s.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	escID, err := s.CreateEscalation(id, "waiting_input", "which base?", "", "", "")
	require.NoError(t, err)

	require.NoError(t, s.ResolveEscalation(escID, "answer", "", "use main"))
	esc, err := s.GetEscalation(escID)
	require.NoError(t, err)
	require.Equal(t, "answer", esc.Resolution)
	require.Equal(t, "use main", esc.Answer)
}
