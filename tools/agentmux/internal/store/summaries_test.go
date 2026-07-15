package store

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_LoadWorktreeSummaries(t *testing.T) {
	t.Run("reads worktrees.json from a project dir", func(t *testing.T) {
		proj := t.TempDir()
		require.NoError(t, os.WriteFile(
			filepath.Join(proj, "worktrees.json"),
			[]byte(`{"wt-a":"do a thing","wt-b":"do b thing"}`), 0o644))
		got := LoadWorktreeSummaries(proj)
		assert.Equal(t, "do a thing", got["wt-a"])
	})
	t.Run("missing file yields empty map", func(t *testing.T) {
		got := LoadWorktreeSummaries(t.TempDir())
		assert.Empty(t, got)
	})
	t.Run("corrupt json yields empty map", func(t *testing.T) {
		proj := t.TempDir()
		require.NoError(t, os.WriteFile(
			filepath.Join(proj, "worktrees.json"), []byte("{not json"), 0o644))
		assert.Empty(t, LoadWorktreeSummaries(proj))
	})
}
