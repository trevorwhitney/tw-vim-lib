package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_FuzzyMatch(t *testing.T) {
	t.Run("subsequence match is case-insensitive", func(t *testing.T) {
		assert.True(t, fuzzyMatch("loki", "grafana/LOKI#43"))
		assert.True(t, fuzzyMatch("gl43", "grafana/loki#43"))
		assert.False(t, fuzzyMatch("xyz", "grafana/loki#43"))
	})
	t.Run("empty query matches everything", func(t *testing.T) {
		assert.True(t, fuzzyMatch("", "anything"))
	})
	t.Run("fuzzyFilter keeps matches in order", func(t *testing.T) {
		items := []string{"inbox", "fleet", "history"}
		got := fuzzyFilter("i", items, func(s string) string { return s })
		assert.Equal(t, []string{"inbox", "history"}, got)
	})
	t.Run("fuzzyFilter with empty query returns all items", func(t *testing.T) {
		items := []string{"inbox", "fleet", "history"}
		got := fuzzyFilter("", items, func(s string) string { return s })
		assert.Equal(t, items, got)
	})
	t.Run("fuzzyFilter matches through a key projection", func(t *testing.T) {
		type row struct{ label string }
		items := []row{{"grafana/loki#43"}, {"grafana/mimir#99"}}
		got := fuzzyFilter("loki", items, func(r row) string { return r.label })
		assert.Equal(t, []row{{"grafana/loki#43"}}, got)
	})
}
