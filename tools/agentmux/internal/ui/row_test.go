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
		n := tree.Node{
			Kind: tree.KindWorktree, Depth: 1, Worktree: "feature",
			Working: 0, Waiting: 0, Saved: 3,
			IsMain: false, Validity: "valid", NeedsAttention: false,
		}
		assert.Equal(t, []Segment{
			{Text: "  feature", Role: RoleWorktree},
			{Text: "  [", Role: RoleSep},
			{Text: "0w", Role: RoleCountZero},
			{Text: " · ", Role: RoleSep},
			{Text: "0q", Role: RoleCountZero},
			{Text: " · ", Role: RoleSep},
			{Text: "3s", Role: RoleCountSaved},
			{Text: "]", Role: RoleSep},
			{Text: "  — ", Role: RoleSep},
			{Text: "fix the thing", Role: RoleDefault},
		}, RenderRow(n, "fix the thing", now))
	})

	t.Run("worktree valid main with attention", func(t *testing.T) {
		n := tree.Node{
			Kind: tree.KindWorktree, Depth: 1, Worktree: "loki",
			Working: 2, Waiting: 1, Saved: 0,
			IsMain: true, Validity: "valid", NeedsAttention: true,
		}
		assert.Equal(t, []Segment{
			{Text: "  loki", Role: RoleWorktree},
			{Text: " [main]", Role: RoleMain},
			{Text: "  [", Role: RoleSep},
			{Text: "2w", Role: RoleCountWorking},
			{Text: " · ", Role: RoleSep},
			{Text: "1q", Role: RoleCountWaiting},
			{Text: " · ", Role: RoleSep},
			{Text: "0s", Role: RoleCountZero},
			{Text: "]", Role: RoleSep},
			{Text: " ⚠", Role: RoleAttention},
			{Text: "  — ", Role: RoleSep},
			{Text: "do the thing", Role: RoleDefault},
		}, RenderRow(n, "do the thing", now))
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
		n := tree.Node{
			Kind: tree.KindAgent, Depth: 2, Worktree: "wt",
			Record: store.Record{Mode: "opencode", Idx: 0, Status: "working", UpdatedTS: now},
		}
		assert.Equal(t, []Segment{
			{Text: "    opencode#0", Role: RoleAgentWorking},
			{Text: "  working", Role: RoleAgentWorking},
			{Text: " · live", Role: RoleAge},
		}, RenderRow(n, "", now))
	})

	t.Run("agent saved waiting with attention", func(t *testing.T) {
		n := tree.Node{
			Kind: tree.KindAgent, Depth: 2, Worktree: "wt",
			Record: store.Record{Mode: "opencode", Idx: 1, Status: "waiting", UpdatedTS: now - 7200},
		}
		assert.Equal(t, []Segment{
			{Text: "    opencode#1", Role: RoleAgentWaiting},
			{Text: "  waiting", Role: RoleAgentWaiting},
			{Text: " · saved 2h ago", Role: RoleAge},
			{Text: " ⚠", Role: RoleAttention},
		}, RenderRow(n, "", now))
	})

	t.Run("agent stale working is attention (yellow line)", func(t *testing.T) {
		n := tree.Node{
			Kind: tree.KindAgent, Depth: 2, Worktree: "wt",
			Record: store.Record{Mode: "opencode", Idx: 0, Status: "working", UpdatedTS: now - 300},
		}
		assert.Equal(t, []Segment{
			{Text: "    opencode#0", Role: RoleAgentWaiting},
			{Text: "  working", Role: RoleAgentWaiting},
			{Text: " · saved 5m ago", Role: RoleAge},
			{Text: " ⚠", Role: RoleAttention},
		}, RenderRow(n, "", now))
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
