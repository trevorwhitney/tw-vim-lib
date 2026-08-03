package store

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func openTemp(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "agentd.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func Test_Open_MigratesAndEnablesWAL(t *testing.T) {
	s := openTemp(t)

	var mode string
	require.NoError(t, s.db.QueryRow("PRAGMA journal_mode").Scan(&mode))
	require.Equal(t, "wal", mode)

	for _, table := range []string{"jobs", "events", "decisions", "actions", "escalations", "artifacts"} {
		var name string
		err := s.db.QueryRow(
			"SELECT name FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&name)
		require.NoError(t, err, "table %s missing", table)
	}
}

func Test_Open_IsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agentd.db")
	s1, err := Open(path)
	require.NoError(t, err)
	require.NoError(t, s1.Close())
	s2, err := Open(path)
	require.NoError(t, err)
	require.NoError(t, s2.Close())
}
