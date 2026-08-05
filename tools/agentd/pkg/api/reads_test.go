package api

import (
	"net/http"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// seededServer is the server plus the ids seeded into it.
type seededServer struct {
	srv        *Server
	st         *store.Store
	queuedID   int64
	waitingID  int64
	terminalID int64
	escID      int64
}

func seedServer(t *testing.T) seededServer {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "agentd.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	queued, err := st.CreateJob("pr", "grafana/loki", 42, "a")
	require.NoError(t, err)
	waiting, err := st.CreateJob("pr", "grafana/loki", 43, "b")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(waiting, "waiting_approval"))
	escID, err := st.CreateEscalation(waiting, "waiting_approval", "approve?", "", "merge_pr", "{}")
	require.NoError(t, err)
	terminal, err := st.CreateJob("pr", "grafana/loki", 44, "c")
	require.NoError(t, err)
	require.NoError(t, st.FinishJob(terminal, "done", "acted", "merged"))

	return seededServer{
		srv:        &Server{Store: st, Engine: &engine.Engine{}},
		st:         st,
		queuedID:   queued,
		waitingID:  waiting,
		terminalID: terminal,
		escID:      escID,
	}
}

func serveClient(t *testing.T, srv *Server) *Client {
	t.Helper()
	sock := filepath.Join(t.TempDir(), "agentd.sock")
	ln, err := Listen(sock)
	require.NoError(t, err)
	httpSrv := &http.Server{Handler: srv.Handler()}
	go func() { _ = httpSrv.Serve(ln) }()
	t.Cleanup(func() { _ = httpSrv.Close() })
	return NewClient(sock)
}

func Test_ReadEndpoints(t *testing.T) {
	s := seedServer(t)
	c := serveClient(t, s.srv)

	t.Run("GET /fleet returns non-terminal jobs", func(t *testing.T) {
		jobs, err := c.Fleet()
		require.NoError(t, err)
		var ids []int64
		for _, j := range jobs {
			ids = append(ids, j.ID)
		}
		assert.Equal(t, []int64{s.queuedID, s.waitingID}, ids)
	})
	t.Run("GET /inbox joins escalation to job", func(t *testing.T) {
		items, err := c.Inbox()
		require.NoError(t, err)
		require.Len(t, items, 1)
		assert.Equal(t, s.escID, items[0].Escalation.ID)
		assert.Equal(t, s.waitingID, items[0].Job.ID)
		assert.Equal(t, "grafana/loki", items[0].Job.Repo)
		assert.Equal(t, "merge_pr", items[0].Escalation.ActionKind)
	})
	t.Run("GET /history returns terminal jobs", func(t *testing.T) {
		jobs, err := c.History(50)
		require.NoError(t, err)
		require.Len(t, jobs, 1)
		assert.Equal(t, s.terminalID, jobs[0].ID)
		assert.Equal(t, "done", jobs[0].State)
	})
}

func Test_JobDetail(t *testing.T) {
	s := seedServer(t)
	require.NoError(t, s.st.AddDecision(s.terminalID, "merge-dependency-updates", "act", "ok"))
	_, executed, err := s.st.UpsertAction(s.terminalID, "merge_pr", "{}")
	require.NoError(t, err)
	require.False(t, executed)
	acts, err := s.st.ActionsForJob(s.terminalID)
	require.NoError(t, err)
	require.Len(t, acts, 1)
	require.NoError(t, s.st.MarkActionExecuted(acts[0].ID, "merged", false))
	require.NoError(t, s.st.AddArtifact(s.terminalID, "diff.patch", "/x"))
	require.NoError(t, s.st.AddEvent(s.terminalID, "preparing", ""))

	c := serveClient(t, s.srv)
	d, err := c.JobDetail(s.terminalID)
	require.NoError(t, err)
	assert.Equal(t, s.terminalID, d.Job.ID)
	require.Len(t, d.Decisions, 1)
	assert.Equal(t, "act", d.Decisions[0].Verdict)
	require.Len(t, d.Actions, 1)
	assert.Equal(t, "merge_pr", d.Actions[0].Kind)
	assert.Equal(t, "merged", d.Actions[0].Result)
	require.Len(t, d.Artifacts, 1)
	assert.Equal(t, "diff.patch", d.Artifacts[0].Name)
	require.Len(t, d.Events, 1)
	assert.Equal(t, "preparing", d.Events[0].Type)
}
