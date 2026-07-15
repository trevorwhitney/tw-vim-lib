package store

import (
	"os"
	"path/filepath"
	"strings"
)

// ReapWindowSecs is the default gone-age after which a record is hard-deleted.
const ReapWindowSecs = int64(7 * 24 * 3600)

// Reap deletes mirror files whose worktree path is gone (per statPath) AND whose
// file mtime (per mtimeOf) is older than olderThanSecs. Returns the count
// deleted. statPath/mtimeOf are injected for testability.
func Reap(dir string, now int64, statPath func(string) bool, mtimeOf func(string) int64, olderThanSecs int64) int {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	reaped := 0
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".json") || strings.HasSuffix(name, ".tmp") {
			continue
		}
		full := filepath.Join(dir, name)
		data, err := os.ReadFile(full)
		if err != nil {
			continue
		}
		rec, err := ParseRecord(data)
		if err != nil {
			continue
		}
		if rec.Schema != SchemaVersion {
			continue
		}
		if statPath(rec.Path) {
			continue
		}
		if now-mtimeOf(full) <= olderThanSecs {
			continue
		}
		if os.Remove(full) == nil {
			reaped++
		}
	}
	return reaped
}
