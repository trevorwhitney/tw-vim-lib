package api

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

func Test_ConvertJob(t *testing.T) {
	in := store.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done",
		Outcome: "acted", FinishedTS: 300}
	out := jobDTO(in)
	assert.Equal(t, int64(3), out.ID)
	assert.Equal(t, "grafana/loki", out.Repo)
	assert.Equal(t, 44, out.PRNumber)
	assert.Equal(t, "done", out.State)
	assert.Equal(t, int64(300), out.FinishedTS)
}

func Test_ConvertEscalation(t *testing.T) {
	in := store.Escalation{ID: 10, JobID: 2, Kind: "waiting_approval", ActionKind: "merge_pr"}
	out := escalationDTO(in)
	assert.Equal(t, int64(10), out.ID)
	assert.Equal(t, "merge_pr", out.ActionKind)
}

func Test_ConvertRepoStatus(t *testing.T) {
	out := repoStatusDTOs([]engine.RepoStatus{{Repo: "r", AuthError: true}})
	assert.Len(t, out, 1)
	assert.Equal(t, "r", out[0].Repo)
	assert.True(t, out[0].AuthError)
}

func Test_ConvertActionRead(t *testing.T) {
	out := actionDTOs([]store.ActionRead{{
		ID: 1, JobID: 3, TS: 220, Kind: "merge_pr", ParamsJSON: "{}",
		Simulated: true, ExecutedTS: 230, Result: "merged", Error: "boom",
	}})
	require.Len(t, out, 1)
	a := out[0]
	assert.Equal(t, int64(1), a.ID)
	assert.Equal(t, int64(3), a.JobID)
	assert.Equal(t, int64(220), a.TS)
	assert.Equal(t, "merge_pr", a.Kind)
	assert.Equal(t, "{}", a.ParamsJSON)
	assert.True(t, a.Simulated)
	assert.Equal(t, int64(230), a.ExecutedTS)
	assert.Equal(t, "merged", a.Result)
	assert.Equal(t, "boom", a.Error)
}

func Test_ConvertInboxItem(t *testing.T) {
	out := inboxItemDTOs([]store.InboxItem{{
		Escalation: store.Escalation{ID: 10, Kind: "waiting_approval", ActionKind: "merge_pr"},
		Job:        store.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43},
	}})
	require.Len(t, out, 1)
	assert.Equal(t, int64(10), out[0].Escalation.ID)
	assert.Equal(t, "merge_pr", out[0].Escalation.ActionKind)
	assert.Equal(t, int64(2), out[0].Job.ID)
	assert.Equal(t, "grafana/loki", out[0].Job.Repo)
	assert.Equal(t, 43, out[0].Job.PRNumber)
}
