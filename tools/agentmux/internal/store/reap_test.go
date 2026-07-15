package store

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Reap(t *testing.T) {
	const now = int64(1_000_000)
	const week = int64(7 * 24 * 3600)
	good := `{"project":"loki","worktree":"wt","path":"/w/loki/wt","handle":"wt","mode":"opencode","idx":0,"status":"restorable","updated_ts":5,"schema":1}`

	write := func(t *testing.T, dir, name string) string {
		p := filepath.Join(dir, name)
		require.NoError(t, os.WriteFile(p, []byte(good), 0o644))
		return p
	}

	t.Run("reaps gone records older than the window", func(t *testing.T) {
		dir := t.TempDir()
		p := write(t, dir, "loki__wt__opencode#0.json")
		gone := func(string) bool { return false }
		mtimeOf := func(string) int64 { return now - week - 1 }
		n := Reap(dir, now, gone, mtimeOf, week)
		assert.Equal(t, 1, n)
		_, err := os.Stat(p)
		assert.True(t, os.IsNotExist(err))
	})

	t.Run("keeps gone records younger than the window", func(t *testing.T) {
		dir := t.TempDir()
		write(t, dir, "loki__wt__opencode#0.json")
		gone := func(string) bool { return false }
		mtimeOf := func(string) int64 { return now - 60 }
		assert.Equal(t, 0, Reap(dir, now, gone, mtimeOf, week))
	})

	t.Run("keeps valid records regardless of age", func(t *testing.T) {
		dir := t.TempDir()
		write(t, dir, "loki__wt__opencode#0.json")
		valid := func(string) bool { return true }
		mtimeOf := func(string) int64 { return 0 }
		assert.Equal(t, 0, Reap(dir, now, valid, mtimeOf, week))
	})

	t.Run("preserves records of an unknown schema even when gone and old", func(t *testing.T) {
		dir := t.TempDir()
		future := `{"project":"loki","worktree":"wt","path":"/w/loki/wt","handle":"wt","mode":"opencode","idx":0,"status":"restorable","updated_ts":5,"schema":99}`
		p := filepath.Join(dir, "loki__wt__opencode#0.json")
		require.NoError(t, os.WriteFile(p, []byte(future), 0o644))
		gone := func(string) bool { return false }
		mtimeOf := func(string) int64 { return now - week - 1 }
		assert.Equal(t, 0, Reap(dir, now, gone, mtimeOf, week))
		_, err := os.Stat(p)
		assert.NoError(t, err, "unknown-schema record must survive")
	})
}
