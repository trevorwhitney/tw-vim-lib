package store

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Load(t *testing.T) {
	write := func(t *testing.T, dir, name, content string) {
		require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644))
	}
	good := `{"project":"loki","worktree":"wt","path":"/w/loki/wt","handle":"wt","mode":"opencode","idx":0,"status":"working","updated_ts":5,"schema":1}`

	t.Run("loads valid records and skips junk", func(t *testing.T) {
		dir := t.TempDir()
		write(t, dir, "loki__wt__opencode#0.json", good)
		write(t, dir, "broken.json", "{not json")
		write(t, dir, "leftover.json.tmp", good)
		write(t, dir, "future.json", `{"project":"x","schema":99}`)

		recs, err := Load(dir)
		assert.NoError(t, err)
		require.Len(t, recs, 1)
		assert.Equal(t, "loki", recs[0].Project)
	})

	t.Run("missing dir returns empty, no error", func(t *testing.T) {
		recs, err := Load(filepath.Join(t.TempDir(), "nope"))
		assert.NoError(t, err)
		assert.Empty(t, recs)
	})
}
