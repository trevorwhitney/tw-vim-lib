package ui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func pressRune(r rune) tea.KeyPressMsg { return tea.KeyPressMsg{Text: string(r)} }

func Test_TabSwitching(t *testing.T) {
	m := New(Deps{MirrorDir: t.TempDir()})
	require.Equal(t, TabInbox, m.activeTab)

	t.Run("] moves to next tab", func(t *testing.T) {
		next, _ := m.Update(pressRune(']'))
		assert.Equal(t, TabFleet, next.(Model).activeTab)
	})
	t.Run("[ moves to previous tab (wraps to History)", func(t *testing.T) {
		prev, _ := m.Update(pressRune('['))
		assert.Equal(t, TabHistory, prev.(Model).activeTab)
	})
	t.Run("Interactive tab preserves filter mode entry", func(t *testing.T) {
		m2 := m
		m2.activeTab = TabInteractive
		after, _ := m2.Update(pressRune('/'))
		assert.True(t, after.(Model).filtering)
	})
}
