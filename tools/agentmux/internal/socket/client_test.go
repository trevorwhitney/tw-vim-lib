package socket

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

type captured struct {
	method string
	path   string
	body   string
}

func serve(t *testing.T, mux *http.ServeMux) string {
	t.Helper()
	// A relative socket path keeps sun_path under the OS limit even in deep
	// sandboxed build directories.
	t.Chdir(t.TempDir())
	const sock = "agentd.sock"
	ln, err := net.Listen("unix", sock)
	require.NoError(t, err)
	srv := &http.Server{Handler: mux}
	go func() { _ = srv.Serve(ln) }()
	t.Cleanup(func() { _ = srv.Close() })
	return sock
}

func Test_ClientReads(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/inbox", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(apitypes.InboxResponse{Items: []apitypes.InboxItem{
			{Escalation: apitypes.Escalation{ID: 10, Kind: "waiting_approval"},
				Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43}},
		}})
	})
	mux.HandleFunc("/fleet", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(apitypes.JobsResponse{Jobs: []apitypes.Job{{ID: 1, State: "queued"}}})
	})
	mux.HandleFunc("/history", func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "50", r.URL.Query().Get("limit"))
		_ = json.NewEncoder(w).Encode(apitypes.JobsResponse{Jobs: []apitypes.Job{{ID: 3, State: "done"}}})
	})
	mux.HandleFunc("/jobs/3", func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "1", r.URL.Query().Get("detail"))
		_ = json.NewEncoder(w).Encode(apitypes.JobDetail{
			Job:       apitypes.Job{ID: 3, State: "done"},
			Decisions: []apitypes.Decision{{Policy: "p", Verdict: "act"}},
		})
	})
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(apitypes.Status{Paused: true, OpenEscalations: 1,
			Repos: []apitypes.RepoStatus{{Repo: "grafana/loki", LastPollTS: 100}}})
	})

	c := NewClient(serve(t, mux))

	t.Run("Inbox", func(t *testing.T) {
		items, err := c.Inbox()
		require.NoError(t, err)
		require.Len(t, items, 1)
		assert.Equal(t, int64(10), items[0].Escalation.ID)
		assert.Equal(t, "grafana/loki", items[0].Job.Repo)
	})
	t.Run("Fleet", func(t *testing.T) {
		jobs, err := c.Fleet()
		require.NoError(t, err)
		require.Len(t, jobs, 1)
		assert.Equal(t, int64(1), jobs[0].ID)
	})
	t.Run("History passes limit", func(t *testing.T) {
		jobs, err := c.History(50)
		require.NoError(t, err)
		require.Len(t, jobs, 1)
		assert.Equal(t, "done", jobs[0].State)
	})
	t.Run("JobDetail passes detail=1", func(t *testing.T) {
		d, err := c.JobDetail(3)
		require.NoError(t, err)
		assert.Equal(t, int64(3), d.Job.ID)
		require.Len(t, d.Decisions, 1)
		assert.Equal(t, "act", d.Decisions[0].Verdict)
	})
	t.Run("Status", func(t *testing.T) {
		st, err := c.Status()
		require.NoError(t, err)
		assert.True(t, st.Paused)
		assert.Equal(t, 1, st.OpenEscalations)
		require.Len(t, st.Repos, 1)
	})
}

func Test_ClientMutations(t *testing.T) {
	var got captured
	mux := http.NewServeMux()
	record := func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		got = captured{r.Method, r.URL.Path, string(b)}
		_, _ = w.Write([]byte(`{"ok":true}`))
	}
	mux.HandleFunc("/escalations/10/resolve", record)
	mux.HandleFunc("/jobs/2/dropin", record)
	mux.HandleFunc("/jobs/2/handback", record)
	mux.HandleFunc("/jobs/2/retry", record)
	mux.HandleFunc("/control/polling", record)
	mux.HandleFunc("/control/gc", record)
	mux.HandleFunc("/policies/grafana/loki/consult-triage/shadow", record)

	c := NewClient(serve(t, mux))

	t.Run("Resolve posts to the escalation id", func(t *testing.T) {
		require.NoError(t, c.Resolve(10, "approve", "", ""))
		assert.Equal(t, http.MethodPost, got.method)
		assert.Equal(t, "/escalations/10/resolve", got.path)
		assert.JSONEq(t, `{"resolution":"approve","reason":"","answer":""}`, got.body)
	})
	t.Run("Reject carries reason", func(t *testing.T) {
		require.NoError(t, c.Resolve(10, "reject", "bad", ""))
		assert.JSONEq(t, `{"resolution":"reject","reason":"bad","answer":""}`, got.body)
	})
	t.Run("DropIn/Handback/Retry are empty-body posts by job id", func(t *testing.T) {
		require.NoError(t, c.DropIn(2))
		assert.Equal(t, "/jobs/2/dropin", got.path)
		assert.JSONEq(t, `{}`, got.body)
		require.NoError(t, c.Handback(2))
		assert.Equal(t, "/jobs/2/handback", got.path)
		require.NoError(t, c.Retry(2))
		assert.Equal(t, "/jobs/2/retry", got.path)
	})
	t.Run("SetPolling", func(t *testing.T) {
		require.NoError(t, c.SetPolling(true))
		assert.JSONEq(t, `{"paused":true}`, got.body)
	})
	t.Run("GC", func(t *testing.T) {
		require.NoError(t, c.GC(0, false))
		assert.JSONEq(t, `{"job_id":0,"force":false}`, got.body)
		require.NoError(t, c.GC(2, true))
		assert.JSONEq(t, `{"job_id":2,"force":true}`, got.body)
	})
	t.Run("SetShadow splits repo into owner/name path", func(t *testing.T) {
		require.NoError(t, c.SetShadow("grafana/loki", "consult-triage", true))
		assert.Equal(t, "/policies/grafana/loki/consult-triage/shadow", got.path)
		assert.JSONEq(t, `{"enabled":true}`, got.body)
	})
}

func Test_ClientError(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/jobs/2/retry", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusConflict)
		_, _ = w.Write([]byte(`{"error":"job not failed"}`))
	})
	c := NewClient(serve(t, mux))
	err := c.Retry(2)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "job not failed")
}
