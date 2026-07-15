// tools/agentmux/internal/tree/tree_test.go
package tree

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
)

func Test_Build(t *testing.T) {
	const now = int64(1000)
	always := func(string) bool { return true }

	t.Run("groups by project then worktree then agent", func(t *testing.T) {
		recs := []store.Record{
			{Project: "loki", Worktree: "wt-a", Mode: "agent", Idx: 1, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
			{Project: "loki", Worktree: "wt-a", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
		}
		nodes := Build(recs, now, always)
		require.GreaterOrEqual(t, len(nodes), 4) // project + worktree + 2 agents
		assert.Equal(t, KindProject, nodes[0].Kind)
		assert.Equal(t, "loki", nodes[0].Project)
		assert.Equal(t, KindWorktree, nodes[1].Kind)
		// agents ordered by idx ascending
		assert.Equal(t, KindAgent, nodes[2].Kind)
		assert.Equal(t, 0, nodes[2].Record.Idx)
		assert.Equal(t, 1, nodes[3].Record.Idx)
	})

	t.Run("main worktree is listed first and tagged", func(t *testing.T) {
		recs := []store.Record{
			{Project: "loki", Worktree: "feature", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
			{Project: "loki", Worktree: "loki", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
		}
		nodes := Build(recs, now, always)
		// first worktree node under the project is the main one
		var firstWT *Node
		for i := range nodes {
			if nodes[i].Kind == KindWorktree {
				firstWT = &nodes[i]
				break
			}
		}
		require.NotNil(t, firstWT)
		assert.Equal(t, "loki", firstWT.Worktree)
		assert.True(t, firstWT.IsMain)
	})

	t.Run("attention worktrees sort before calm ones", func(t *testing.T) {
		recs := []store.Record{
			{Project: "loki", Worktree: "calm", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
			{Project: "loki", Worktree: "needy", Mode: "agent", Idx: 0, Status: "waiting", UpdatedTS: now, Path: "/p", Schema: 1},
		}
		nodes := Build(recs, now, always)
		var order []string
		for _, n := range nodes {
			if n.Kind == KindWorktree {
				order = append(order, n.Worktree)
			}
		}
		assert.Equal(t, []string{"needy", "calm"}, order)
	})

	t.Run("gone worktree is flagged via validity", func(t *testing.T) {
		none := func(string) bool { return false }
		recs := []store.Record{
			{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/gone", Schema: 1},
		}
		nodes := Build(recs, now, none)
		var wt *Node
		for i := range nodes {
			if nodes[i].Kind == KindWorktree {
				wt = &nodes[i]
			}
		}
		require.NotNil(t, wt)
		assert.Equal(t, "gone", wt.Validity)
	})

	t.Run("rollup counts are disjoint and sum to agent total", func(t *testing.T) {
		recs := []store.Record{
			{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},       // live working
			{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 1, Status: "waiting", UpdatedTS: now, Path: "/p", Schema: 1},       // live waiting
			{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 2, Status: "working", UpdatedTS: now - 100, Path: "/p", Schema: 1}, // saved working
			{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 3, Status: "waiting", UpdatedTS: now - 100, Path: "/p", Schema: 1}, // saved waiting → waiting bucket
		}
		nodes := Build(recs, now, func(string) bool { return true })
		var wt *Node
		for i := range nodes {
			if nodes[i].Kind == KindWorktree {
				wt = &nodes[i]
			}
		}
		require.NotNil(t, wt)
		assert.Equal(t, 1, wt.Working, "working = live non-waiting")
		assert.Equal(t, 2, wt.Waiting, "waiting = any waiting")
		assert.Equal(t, 1, wt.Saved, "saved = non-live non-waiting")
		assert.Equal(t, 4, wt.Working+wt.Waiting+wt.Saved, "buckets sum to total")
	})

	t.Run("saved worktrees with equal age order deterministically by name", func(t *testing.T) {
		none := func(string) bool { return true }
		recs := []store.Record{
			{Project: "loki", Worktree: "zeta", Mode: "opencode", Idx: 0, Status: "working", UpdatedTS: now - 100, Path: "/p", Schema: 1},
			{Project: "loki", Worktree: "alpha", Mode: "opencode", Idx: 0, Status: "working", UpdatedTS: now - 100, Path: "/p", Schema: 1},
		}
		var order []string
		for _, n := range Build(recs, now, none) {
			if n.Kind == KindWorktree {
				order = append(order, n.Worktree)
			}
		}
		assert.Equal(t, []string{"alpha", "zeta"}, order, "equal-age saved worktrees sort by name")
	})
}
