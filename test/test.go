package test

import (
	"github.com/stretchr/testify/assert"
	"testing"
)

func Test_FooBar(t *testing.T) {
	t.Run("it is not bar", func(t *testing.T) {
		assert.True(t, true)

		t.Run("it is a really nested test", func(t *testing.T) {
			assert.False(t, false)
		})

		t.Run("second nested test is sibling", func(t *testing.T) {
			assert.False(t, false)
		})

		t.Run("living in the middle", func(t *testing.T) {
			t.Run("living on the edge", func(t *testing.T) {
				assert.True(t, true)
			})
		})
	})

	t.Run("this should be on it's own", func(t *testing.T) {
		assert.True(t, true)
	})
}
