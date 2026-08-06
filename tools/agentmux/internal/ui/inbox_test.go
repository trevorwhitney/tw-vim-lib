package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func Test_RenderInboxRow(t *testing.T) {
	const now = int64(1000)
	t.Run("approval item with attached action", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{
				ID: 10, Kind: "waiting_approval", TS: 940,
				Question: "approve merge?", ActionKind: "merge_pr",
			},
			Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43},
		}
		assert.Equal(t, []Segment{
			{Text: "⚑ ", Role: RoleStateWaiting},
			{Text: "grafana/loki#43", Role: RoleRepo},
			{Text: "  1m", Role: RoleAge},
			{Text: "  merge_pr", Role: RoleVerdict},
			{Text: "  — ", Role: RoleSep},
			{Text: "approve merge?", Role: RoleDefault},
		}, renderInboxRow(it, now))
	})
	t.Run("input item shows a question marker and no action", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{
				ID: 11, Kind: "waiting_input", TS: 1000, Question: "which base?",
			},
			Job: apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44},
		}
		got := renderInboxRow(it, now)
		// No verdict/action segment for input items.
		for _, s := range got {
			assert.NotEqual(t, RoleVerdict, s.Role)
		}
		assert.Equal(t, Segment{Text: "? ", Role: RoleStateWaiting}, got[0])
	})
	t.Run("attention item uses the attention role", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{ID: 12, Kind: "attention", TS: 1000,
				Question: "worktree has uncommitted changes"},
			Job: apitypes.Job{ID: 4, Repo: "grafana/loki", PRNumber: 45},
		}
		assert.Equal(t, Segment{Text: "⚠ ", Role: RoleAttention}, renderInboxRow(it, now)[0])
	})
	t.Run("unknown kind falls back to the default marker", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{ID: 13, Kind: "", TS: 1000, Question: "hm?"},
			Job:        apitypes.Job{ID: 5, Repo: "grafana/loki", PRNumber: 46},
		}
		assert.Equal(t, Segment{Text: "• ", Role: RoleSep}, renderInboxRow(it, now)[0])
	})
	t.Run("empty question falls back to job summary", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{ID: 14, Kind: "attention", TS: 1000},
			Job:        apitypes.Job{ID: 6, Repo: "grafana/loki", PRNumber: 47, Summary: "cleanup failed"},
		}
		got := renderInboxRow(it, now)
		assert.Equal(t, Segment{Text: "cleanup failed", Role: RoleDefault}, got[len(got)-1])
	})
	t.Run("no question and no summary omits the trailing separator", func(t *testing.T) {
		it := apitypes.InboxItem{
			Escalation: apitypes.Escalation{ID: 15, Kind: "attention", TS: 1000},
			Job:        apitypes.Job{ID: 7, Repo: "grafana/loki", PRNumber: 48},
		}
		for _, s := range renderInboxRow(it, now) {
			assert.NotEqual(t, RoleSep, s.Role, "no RoleSep trailer when question and summary are both empty")
		}
	})
}
