package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_Record(t *testing.T) {
	t.Run("parses a well-formed record JSON", func(t *testing.T) {
		raw := []byte(`{
			"project":"loki","worktree":"logmerge-build-index",
			"path":"/w/loki/logmerge-build-index","handle":"logmerge-build-index",
			"mode":"opencode","idx":0,"status":"working",
			"description":"add compaction metrics","session_id":"ses_1",
			"updated_ts":111,"schema":1
		}`)
		rec, err := ParseRecord(raw)
		assert.NoError(t, err)
		assert.Equal(t, "loki", rec.Project)
		assert.Equal(t, "opencode", rec.Mode)
		assert.Equal(t, 0, rec.Idx)
		assert.Equal(t, "working", rec.Status)
		assert.Equal(t, int64(111), rec.UpdatedTS)
		assert.Equal(t, 1, rec.Schema)
	})

	t.Run("errors on malformed JSON", func(t *testing.T) {
		_, err := ParseRecord([]byte("{not json"))
		assert.Error(t, err)
	})
}
