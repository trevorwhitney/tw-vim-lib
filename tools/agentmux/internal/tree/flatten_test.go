// tools/agentmux/internal/tree/flatten_test.go
package tree

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
)

func Test_Flatten(t *testing.T) {
	const now = int64(1000)
	always := func(string) bool { return true }
	recs := []store.Record{
		{Project: "loki", Worktree: "wt", Mode: "agent", Idx: 0, Status: "working", UpdatedTS: now, Path: "/p", Schema: 1},
	}
	nodes := Build(recs, now, always)

	t.Run("nothing collapsed shows all", func(t *testing.T) {
		vis := Flatten(nodes, map[string]bool{})
		assert.Len(t, vis, 3) // project, worktree, agent
	})
	t.Run("collapsed worktree hides its agents", func(t *testing.T) {
		vis := Flatten(nodes, map[string]bool{"w:loki/wt": true})
		assert.Len(t, vis, 2) // project, worktree
	})
	t.Run("collapsed project hides worktrees and agents", func(t *testing.T) {
		vis := Flatten(nodes, map[string]bool{"p:loki": true})
		assert.Len(t, vis, 1) // project only
	})
}
