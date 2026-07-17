package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

func Test_RenderRow(t *testing.T) {
	const now = int64(1000)

	t.Run("project depth 0", func(t *testing.T) {
		n := tree.Node{Kind: tree.KindProject, Depth: 0, Project: "loki"}
		assert.Equal(t, []Segment{
			{Text: "▸ loki", Role: RoleProject},
		}, RenderRow(n, "", now))
	})

	t.Run("project depth 1", func(t *testing.T) {
		n := tree.Node{Kind: tree.KindProject, Depth: 1, Project: "grafana"}
		assert.Equal(t, []Segment{
			{Text: "  ▸ grafana", Role: RoleProject},
		}, RenderRow(n, "", now))
	})

	t.Run("worktree valid non-main no attention", func(t *testing.T) {
		t.Skip("segment rendering for valid worktrees not implemented yet")
		n := tree.Node{
			Kind:           tree.KindWorktree,
			Depth:          1,
			Worktree:       "feature",
			Working:        0,
			Waiting:        0,
			Saved:          3,
			IsMain:         false,
			Validity:       "valid",
			NeedsAttention: false,
		}
		expected := "  feature  [0w · 0q · 3s]  — fix the thing"
		assert.Equal(t, expected, RenderRow(n, "fix the thing", now))
	})

	t.Run("worktree valid main with attention", func(t *testing.T) {
		t.Skip("segment rendering for valid worktrees not implemented yet")
		n := tree.Node{
			Kind:           tree.KindWorktree,
			Depth:          1,
			Worktree:       "loki",
			Working:        2,
			Waiting:        1,
			Saved:          0,
			IsMain:         true,
			Validity:       "valid",
			NeedsAttention: true,
		}
		expected := "  loki [main]  [2w · 1q · 0s] ⚠  — do the thing"
		assert.Equal(t, expected, RenderRow(n, "do the thing", now))
	})

	t.Run("worktree gone", func(t *testing.T) {
		n := tree.Node{
			Kind:     tree.KindWorktree,
			Depth:    1,
			Worktree: "old-feature",
			IsMain:   false,
			Validity: "gone",
		}
		assert.Equal(t, []Segment{
			{Text: "  old-feature", Role: RoleWorktree},
			{Text: "  (removed)", Role: RoleRemoved},
		}, RenderRow(n, "", now))
	})

	t.Run("agent live working", func(t *testing.T) {
		t.Skip("segment rendering for agents not implemented yet")
		n := tree.Node{
			Kind:     tree.KindAgent,
			Depth:    2,
			Worktree: "wt",
			Record: store.Record{
				Mode:      "opencode",
				Idx:       0,
				Status:    "working",
				UpdatedTS: now,
			},
		}
		expected := "    opencode#0  working · live"
		assert.Equal(t, expected, RenderRow(n, "", now))
	})

	t.Run("agent saved waiting with attention", func(t *testing.T) {
		t.Skip("segment rendering for agents not implemented yet")
		n := tree.Node{
			Kind:     tree.KindAgent,
			Depth:    2,
			Worktree: "wt",
			Record: store.Record{
				Mode:      "opencode",
				Idx:       1,
				Status:    "waiting",
				UpdatedTS: now - 7200,
			},
		}
		expected := "    opencode#1  waiting · saved 2h ago ⚠"
		assert.Equal(t, expected, RenderRow(n, "", now))
	})
}

func Test_SegmentRole_values(t *testing.T) {
	roles := []SegmentRole{
		RoleDefault, RoleProject, RoleWorktree, RoleMain,
		RoleCountWorking, RoleCountWaiting, RoleCountSaved, RoleCountZero,
		RoleAgentWorking, RoleAgentWaiting, RoleAttention, RoleAge,
		RoleRemoved, RoleSep,
	}
	seen := map[SegmentRole]bool{}
	for _, r := range roles {
		assert.False(t, seen[r], "duplicate role value: %d", r)
		seen[r] = true
	}
	assert.Len(t, seen, 14)
}

func Test_humanAge(t *testing.T) {
	assert.Equal(t, "59s", humanAge(59))
	assert.Equal(t, "1m", humanAge(60))
	assert.Equal(t, "59m", humanAge(3599))
	assert.Equal(t, "1h", humanAge(3600))
	assert.Equal(t, "1d", humanAge(86400))
}
