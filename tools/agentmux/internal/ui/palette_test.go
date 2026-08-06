package ui

import (
	"testing"

	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func Test_Palette(t *testing.T) {
	fc := &fakeClient{}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.activeTab = TabFleet

	t.Run("ctrl+p opens palette with commands", func(t *testing.T) {
		after, _ := m.Update(tea.KeyPressMsg{Text: "ctrl+p"})
		am := after.(Model)
		assert.True(t, am.paletteOpen)
		assert.NotEmpty(t, am.paletteCommands())
	})
	t.Run("typing filters commands", func(t *testing.T) {
		m2 := m
		m2.paletteOpen = true
		m2.paletteQuery = "pause"
		visible := m2.paletteVisible()
		require.NotEmpty(t, visible)
		for _, c := range visible {
			assert.True(t, fuzzyMatch("pause", c.label))
		}
	})
	t.Run("switch-to-tab command changes tab", func(t *testing.T) {
		m2 := m
		m2.paletteOpen = true
		m2.paletteQuery = "history"
		vis := m2.paletteVisible()
		require.NotEmpty(t, vis)
		next, _ := vis[0].run(m2)
		assert.Equal(t, TabHistory, next.(Model).activeTab)
		assert.False(t, next.(Model).paletteOpen)
	})
}

func Test_PaletteHandler(t *testing.T) {
	fc := &fakeClient{}
	newPalette := func() Model {
		m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
		m.activeTab = TabFleet
		m.paletteOpen = true
		return m
	}

	t.Run("esc closes and clears the query", func(t *testing.T) {
		m := newPalette()
		m.paletteQuery = "pau"
		after, _ := m.Update(tea.KeyPressMsg{Text: "esc"})
		am := after.(Model)
		assert.False(t, am.paletteOpen)
		assert.Empty(t, am.paletteQuery)
	})
	t.Run("enter dispatches the selected command through the handler", func(t *testing.T) {
		m := newPalette()
		m.paletteQuery = "history"
		after, _ := m.Update(tea.KeyPressMsg{Text: "enter"})
		am := after.(Model)
		assert.Equal(t, TabHistory, am.activeTab)
		assert.False(t, am.paletteOpen)
	})
	t.Run("enter after the filtered list shrinks does not panic", func(t *testing.T) {
		m := newPalette()
		// Move deep into the unfiltered list, then shrink it with a query.
		for range 6 {
			next, _ := m.Update(tea.KeyPressMsg{Text: "down"})
			m = next.(Model)
		}
		for _, r := range "history" {
			next, _ := m.Update(pressRune(r))
			m = next.(Model)
		}
		after, _ := m.Update(tea.KeyPressMsg{Text: "enter"})
		assert.Equal(t, TabHistory, after.(Model).activeTab)
	})
	t.Run("typing resets the cursor", func(t *testing.T) {
		m := newPalette()
		next, _ := m.Update(tea.KeyPressMsg{Text: "down"})
		m = next.(Model)
		require.Equal(t, 1, m.paletteCur)
		next, _ = m.Update(pressRune('g'))
		assert.Equal(t, 0, next.(Model).paletteCur)
	})
}

func Test_PalettePauseLabel(t *testing.T) {
	fc := &fakeClient{}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})

	labels := func(mm Model) []string {
		var out []string
		for _, c := range mm.paletteCommands() {
			out = append(out, c.label)
		}
		return out
	}
	m.status.Paused = false
	assert.Contains(t, labels(m), "Pause polling")
	m.status.Paused = true
	assert.Contains(t, labels(m), "Resume polling")
}

func Test_PaletteModifierEvent(t *testing.T) {
	// A real terminal Ctrl+P arrives as a modifier event, not Text.
	msg := tea.KeyPressMsg{Code: 'p', Mod: tea.ModCtrl}
	assert.True(t, key.Matches(msg, DefaultKeyMap().Palette))
}

func Test_PaletteRespectsOverlays(t *testing.T) {
	fc := &fakeClient{}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.activeTab = TabHistory
	m.history = []apitypes.Job{{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done"}}

	t.Run("ctrl+p does not open over the detail overlay", func(t *testing.T) {
		mm := m
		mm.showDetail = true
		after, _ := mm.Update(tea.KeyPressMsg{Text: "ctrl+p"})
		assert.False(t, after.(Model).paletteOpen)
		assert.True(t, after.(Model).showDetail)
	})
	t.Run("ctrl+p does not open over help and any key dismisses help", func(t *testing.T) {
		mm := m
		mm.showHelp = true
		after, _ := mm.Update(tea.KeyPressMsg{Text: "ctrl+p"})
		am := after.(Model)
		assert.False(t, am.paletteOpen)
		assert.False(t, am.showHelp) // the keypress dismissed help instead
	})
}

func Test_PaletteHelpCommand(t *testing.T) {
	m := New(Deps{MirrorDir: t.TempDir()})
	m.activeTab = TabFleet
	m.paletteOpen = true
	m.paletteQuery = "help"
	vis := m.paletteVisible()
	require.NotEmpty(t, vis)
	next, _ := vis[0].run(m)
	am := next.(Model)
	assert.True(t, am.showHelp)
	assert.False(t, am.paletteOpen)
}
