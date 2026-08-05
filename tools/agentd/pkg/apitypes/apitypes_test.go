package apitypes

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_JobJSONTags(t *testing.T) {
	j := Job{ID: 1, Repo: "grafana/loki", PRNumber: 42, State: "done", FinishedTS: 5}
	b, err := json.Marshal(j)
	require.NoError(t, err)
	var m map[string]any
	require.NoError(t, json.Unmarshal(b, &m))
	for _, k := range []string{"id", "kind", "repo", "pr_number", "head_sha",
		"state", "outcome", "summary", "error", "worktree_path", "session_id",
		"window_id", "verdicts_json", "created_ts", "updated_ts", "finished_ts"} {
		_, ok := m[k]
		assert.True(t, ok, "Job JSON must carry key %q", k)
	}
}

func Test_EscalationJSONTags(t *testing.T) {
	e := Escalation{ID: 1, JobID: 2, Kind: "waiting_approval"}
	b, err := json.Marshal(e)
	require.NoError(t, err)
	var m map[string]any
	require.NoError(t, json.Unmarshal(b, &m))
	for _, k := range []string{"id", "job_id", "ts", "kind", "question", "advice",
		"action_kind", "action_params_json", "state", "resolution", "reason",
		"answer", "last_notified_ts"} {
		_, ok := m[k]
		assert.True(t, ok, "Escalation JSON must carry key %q", k)
	}
}

func Test_StatusJSONTags(t *testing.T) {
	s := Status{Paused: true, OpenEscalations: 2, Repos: []RepoStatus{{Repo: "r"}}}
	b, err := json.Marshal(s)
	require.NoError(t, err)
	var m map[string]any
	require.NoError(t, json.Unmarshal(b, &m))
	for _, k := range []string{"paused", "open_escalations", "repos"} {
		_, ok := m[k]
		assert.True(t, ok, "Status JSON must carry key %q", k)
	}
	var rm map[string]any
	rb, _ := json.Marshal(RepoStatus{Repo: "r"})
	require.NoError(t, json.Unmarshal(rb, &rm))
	for _, k := range []string{"repo", "last_poll_ts", "last_error", "auth_error"} {
		_, ok := rm[k]
		assert.True(t, ok, "RepoStatus JSON must carry key %q", k)
	}
}

func Test_JobResponseJSON(t *testing.T) {
	t.Run("escalation omitted when nil", func(t *testing.T) {
		b, err := json.Marshal(JobResponse{Job: Job{ID: 1}})
		require.NoError(t, err)
		var m map[string]any
		require.NoError(t, json.Unmarshal(b, &m))
		_, hasJob := m["job"]
		_, hasEsc := m["escalation"]
		assert.True(t, hasJob, "job key must always be present")
		assert.False(t, hasEsc, "escalation must be omitted when nil")
	})
	t.Run("escalation present when set", func(t *testing.T) {
		b, err := json.Marshal(JobResponse{Job: Job{ID: 1}, Escalation: &Escalation{ID: 10}})
		require.NoError(t, err)
		var m map[string]any
		require.NoError(t, json.Unmarshal(b, &m))
		_, hasEsc := m["escalation"]
		assert.True(t, hasEsc, "escalation must be present when non-nil")
	})
}
