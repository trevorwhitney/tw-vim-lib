package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func seedReads(t *testing.T) *Store {
	t.Helper()
	s, err := Open(t.TempDir() + "/agentd.db")
	require.NoError(t, err)
	t.Cleanup(func() { _ = s.Close() })
	// queued (non-terminal), no escalation
	_, err = s.db.Exec(`INSERT INTO jobs (id, kind, repo, pr_number, head_sha, state, created_ts, updated_ts)
		VALUES (1, 'pr', 'grafana/loki', 42, 'a', 'queued', 100, 100)`)
	require.NoError(t, err)
	// waiting_approval + open escalation
	_, err = s.db.Exec(`INSERT INTO jobs (id, kind, repo, pr_number, head_sha, state, summary, created_ts, updated_ts)
		VALUES (2, 'pr', 'grafana/loki', 43, 'b', 'waiting_approval', 'safe', 100, 200)`)
	require.NoError(t, err)
	_, err = s.db.Exec(`INSERT INTO escalations (id, job_id, ts, kind, question, action_kind)
		VALUES (10, 2, 150, 'waiting_approval', 'approve?', 'merge_pr')`)
	require.NoError(t, err)
	// terminal
	_, err = s.db.Exec(`INSERT INTO jobs (id, kind, repo, pr_number, head_sha, state, outcome, created_ts, updated_ts, finished_ts)
		VALUES (3, 'pr', 'grafana/loki', 44, 'c', 'done', 'acted', 100, 300, 300)`)
	require.NoError(t, err)
	// a resolved escalation must NOT appear in the inbox
	_, err = s.db.Exec(`INSERT INTO escalations (id, job_id, ts, kind, question, state, resolution)
		VALUES (11, 3, 250, 'waiting_approval', 'old?', 'resolved', 'approve')`)
	require.NoError(t, err)
	return s
}

func Test_TerminalJobs(t *testing.T) {
	s := seedReads(t)
	jobs, err := s.TerminalJobs(50)
	require.NoError(t, err)
	require.Len(t, jobs, 1)
	assert.Equal(t, int64(3), jobs[0].ID)
	assert.Equal(t, "done", jobs[0].State)
}

func Test_InboxItems(t *testing.T) {
	s := seedReads(t)
	items, err := s.InboxItems()
	require.NoError(t, err)
	require.Len(t, items, 1)
	assert.Equal(t, int64(10), items[0].Escalation.ID)
	assert.Equal(t, int64(2), items[0].Job.ID)
	assert.Equal(t, "grafana/loki", items[0].Job.Repo)
	assert.Equal(t, "merge_pr", items[0].Escalation.ActionKind)
	assert.Equal(t, "open", items[0].Escalation.State)
}
