package ui

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

func writeRecord(t *testing.T, dir, name string, r store.Record) {
	t.Helper()
	data, err := store.EncodeRecord(r)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, name), data, 0o644))
}

func Test_purge(t *testing.T) {
	rec := func(project, worktree, mode string, idx int) store.Record {
		return store.Record{
			Project:  project,
			Worktree: worktree,
			Path:     "/w/" + project + "/" + worktree,
			Mode:     mode,
			Idx:      idx,
			Schema:   1,
		}
	}

	t.Run("agent node deletes only its own record", func(t *testing.T) {
		dir := t.TempDir()
		writeRecord(t, dir, "loki__wt__opencode#0.json", rec("loki", "wt", "opencode", 0))
		writeRecord(t, dir, "loki__wt__opencode#1.json", rec("loki", "wt", "opencode", 1))
		writeRecord(t, dir, "loki__wt__claude#0.json", rec("loki", "wt", "claude", 0))

		m := New(dir)
		m.visible = []tree.Node{
			{Kind: tree.KindAgent, Project: "loki", Worktree: "wt", Record: rec("loki", "wt", "opencode", 1)},
		}
		m.cursor = 0
		m.purge()

		assert.FileExists(t, filepath.Join(dir, "loki__wt__opencode#0.json"))
		assert.NoFileExists(t, filepath.Join(dir, "loki__wt__opencode#1.json"))
		assert.FileExists(t, filepath.Join(dir, "loki__wt__claude#0.json"))
	})

	t.Run("gone worktree node deletes all its records", func(t *testing.T) {
		dir := t.TempDir()
		writeRecord(t, dir, "loki__wt__opencode#0.json", rec("loki", "wt", "opencode", 0))
		writeRecord(t, dir, "loki__wt__opencode#1.json", rec("loki", "wt", "opencode", 1))
		writeRecord(t, dir, "loki__other__opencode#0.json", rec("loki", "other", "opencode", 0))

		m := New(dir)
		m.visible = []tree.Node{
			{Kind: tree.KindWorktree, Project: "loki", Worktree: "wt", Validity: "gone"},
		}
		m.cursor = 0
		m.purge()

		assert.NoFileExists(t, filepath.Join(dir, "loki__wt__opencode#0.json"))
		assert.NoFileExists(t, filepath.Join(dir, "loki__wt__opencode#1.json"))
		assert.FileExists(t, filepath.Join(dir, "loki__other__opencode#0.json"))
	})

	t.Run("valid worktree node is rejected", func(t *testing.T) {
		dir := t.TempDir()
		writeRecord(t, dir, "loki__wt__opencode#0.json", rec("loki", "wt", "opencode", 0))

		m := New(dir)
		m.visible = []tree.Node{
			{Kind: tree.KindWorktree, Project: "loki", Worktree: "wt", Validity: "valid"},
		}
		m.cursor = 0
		m.purge()

		assert.FileExists(t, filepath.Join(dir, "loki__wt__opencode#0.json"))
		assert.Contains(t, m.status, "purge")
	})

	t.Run("project node is rejected", func(t *testing.T) {
		dir := t.TempDir()
		writeRecord(t, dir, "loki__wt__opencode#0.json", rec("loki", "wt", "opencode", 0))

		m := New(dir)
		m.visible = []tree.Node{{Kind: tree.KindProject, Project: "loki"}}
		m.cursor = 0
		m.purge()

		assert.FileExists(t, filepath.Join(dir, "loki__wt__opencode#0.json"))
	})
}
