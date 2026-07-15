package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_Summary(t *testing.T) {
	rec := Record{Project: "loki", Worktree: "logmerge-build-index"}

	t.Run("prefers worktrees.json summary", func(t *testing.T) {
		summaries := map[string]string{"logmerge-build-index": "add compaction metrics"}
		branchOf := func(Record) string { return "feature/x" }
		assert.Equal(t, "add compaction metrics", Summary(rec, summaries, branchOf))
	})
	t.Run("falls back to branch when no summary", func(t *testing.T) {
		branchOf := func(Record) string { return "feature/x" }
		assert.Equal(t, "feature/x", Summary(rec, nil, branchOf))
	})
	t.Run("falls back to worktree name when no branch", func(t *testing.T) {
		branchOf := func(Record) string { return "" }
		assert.Equal(t, "logmerge-build-index", Summary(rec, nil, branchOf))
	})
	t.Run("nil branchOf is tolerated", func(t *testing.T) {
		assert.Equal(t, "logmerge-build-index", Summary(rec, nil, nil))
	})
}
