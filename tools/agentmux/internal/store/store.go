package store

import (
	"os"
	"path/filepath"
	"strings"
)

// SchemaVersion is the only record schema this build understands. Records with a
// different schema are skipped.
const SchemaVersion = 1

// Load reads all recognized records from the mirror directory. Files that fail
// to parse, end in .tmp, or carry an unknown schema are skipped. A missing
// directory yields an empty slice and no error.
func Load(dir string) ([]Record, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var recs []Record
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".json") || strings.HasSuffix(name, ".tmp") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		rec, err := ParseRecord(data)
		if err != nil || rec.Schema != SchemaVersion {
			continue
		}
		recs = append(recs, rec)
	}
	return recs, nil
}
