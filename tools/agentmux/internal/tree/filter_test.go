// tools/agentmux/internal/tree/filter_test.go
package tree

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
)

func Test_Filter(t *testing.T) {
	const now = int64(1000)
	always := func(string) bool { return true }
	recs := []store.Record{
		{Project: "loki", Worktree: "compaction", Mode: "agent", Idx: 0, Status: "working", Description: "add metrics", UpdatedTS: now, Path: "/p", Schema: 1},
		{Project: "loki", Worktree: "ingester", Mode: "agent", Idx: 0, Status: "working", Description: "fix wal", UpdatedTS: now, Path: "/p", Schema: 1},
	}
	nodes := Build(recs, now, always)

	worktrees := func(ns []Node) []string {
		var out []string
		for _, n := range ns {
			if n.Kind == KindWorktree {
				out = append(out, n.Worktree)
			}
		}
		return out
	}

	t.Run("empty query returns all", func(t *testing.T) {
		assert.Equal(t, []string{"compaction", "ingester"}, worktrees(Filter(nodes, "")))
	})
	t.Run("matches worktree name", func(t *testing.T) {
		assert.Equal(t, []string{"compaction"}, worktrees(Filter(nodes, "compac")))
	})
	t.Run("matches agent description", func(t *testing.T) {
		assert.Equal(t, []string{"ingester"}, worktrees(Filter(nodes, "wal")))
	})
	t.Run("drops project header when no worktree matches", func(t *testing.T) {
		filtered := Filter(nodes, "nonexistent")
		assert.Empty(t, filtered)
	})
	t.Run("case-insensitive", func(t *testing.T) {
		assert.Equal(t, []string{"compaction"}, worktrees(Filter(nodes, "COMPAC")))
	})
}
