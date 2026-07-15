package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_Derive(t *testing.T) {
	const now = int64(1000)

	t.Run("liveness within window is live", func(t *testing.T) {
		assert.Equal(t, "live", Liveness(Record{UpdatedTS: now - 5}, now))
	})
	t.Run("liveness past window is saved", func(t *testing.T) {
		assert.Equal(t, "saved", Liveness(Record{UpdatedTS: now - 20}, now))
	})
	t.Run("age is now minus updated", func(t *testing.T) {
		assert.Equal(t, int64(30), AgeSecs(Record{UpdatedTS: now - 30}, now))
	})
	t.Run("validity is filesystem-canonical", func(t *testing.T) {
		exists := func(p string) bool { return p == "/w/loki/wt" }
		assert.Equal(t, "valid", Validity("/w/loki/wt", exists))
		assert.Equal(t, "gone", Validity("/w/loki/removed", exists))
	})
	t.Run("waiting needs attention even if live", func(t *testing.T) {
		assert.True(t, NeedsAttention(Record{Status: "waiting", UpdatedTS: now}, now))
	})
	t.Run("saved needs attention", func(t *testing.T) {
		assert.True(t, NeedsAttention(Record{Status: "working", UpdatedTS: now - 100}, now))
	})
	t.Run("live and working does not need attention", func(t *testing.T) {
		assert.False(t, NeedsAttention(Record{Status: "working", UpdatedTS: now}, now))
	})
}
