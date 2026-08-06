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

func Test_DetailReaders(t *testing.T) {
	s := seedReads(t)
	_, err := s.db.Exec(`INSERT INTO decisions (id, job_id, ts, policy, verdict, rationale)
		VALUES (1, 3, 210, 'merge-dependency-updates', 'act', 'ok')`)
	require.NoError(t, err)
	_, err = s.db.Exec(`INSERT INTO actions (id, job_id, ts, kind, params_json, params_hash, simulated, executed_ts, result)
		VALUES (1, 3, 220, 'merge_pr', '{}', 'h', 0, 230, 'merged')`)
	require.NoError(t, err)
	// an unexecuted action: executed_ts is NULL -> must read back as 0
	_, err = s.db.Exec(`INSERT INTO actions (id, job_id, ts, kind, params_json, params_hash, simulated)
		VALUES (2, 3, 240, 'comment_pr', '{}', 'h2', 0)`)
	require.NoError(t, err)
	_, err = s.db.Exec(`INSERT INTO events (id, job_id, ts, type, payload_json)
		VALUES (1, 3, 205, 'preparing', '')`)
	require.NoError(t, err)

	t.Run("DecisionsForJob", func(t *testing.T) {
		ds, err := s.DecisionsForJob(3)
		require.NoError(t, err)
		require.Len(t, ds, 1)
		assert.Equal(t, "act", ds[0].Verdict)
	})
	t.Run("ActionsForJob includes ts and executed_ts", func(t *testing.T) {
		as, err := s.ActionsForJob(3)
		require.NoError(t, err)
		require.Len(t, as, 2)
		assert.Equal(t, "merge_pr", as[0].Kind)
		assert.Equal(t, int64(220), as[0].TS)
		assert.Equal(t, int64(230), as[0].ExecutedTS)
		assert.Equal(t, "merged", as[0].Result)
		assert.Equal(t, "comment_pr", as[1].Kind)
		assert.Equal(t, int64(0), as[1].ExecutedTS) // NULL coalesced to 0
	})
	t.Run("EventsForJob", func(t *testing.T) {
		es, err := s.EventsForJob(3)
		require.NoError(t, err)
		require.Len(t, es, 1)
		assert.Equal(t, "preparing", es[0].Type)
	})
}
