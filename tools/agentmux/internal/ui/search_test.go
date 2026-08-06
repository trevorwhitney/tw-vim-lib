package ui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

func Test_GlobalSearch(t *testing.T) {
	m := New(Deps{MirrorDir: t.TempDir()})
	m.inbox = []apitypes.InboxItem{{Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43}, Escalation: apitypes.Escalation{ID: 10}}}
	m.fleet = []apitypes.Job{{ID: 5, Repo: "grafana/mimir", PRNumber: 99, State: "running"}}
	m.history = []apitypes.Job{{ID: 9, Repo: "grafana/loki", PRNumber: 12, State: "done"}}

	t.Run("union across tabs", func(t *testing.T) {
		res := m.searchResults("loki")
		var tabs []Tab
		for _, r := range res {
			tabs = append(tabs, r.tab)
		}
		assert.Contains(t, tabs, TabInbox)
		assert.Contains(t, tabs, TabHistory)
		assert.NotContains(t, tabs, TabFleet) // mimir, not loki
	})
	t.Run("selecting a result jumps to its tab and index", func(t *testing.T) {
		res := m.searchResults("mimir")
		require.Len(t, res, 1)
		after := m.gotoResult(res[0])
		assert.Equal(t, TabFleet, after.activeTab)
		assert.Equal(t, 0, after.fleetCur)
		assert.False(t, after.searching)
	})
}

func Test_SearchHandler(t *testing.T) {
	seed := func() Model {
		m := New(Deps{MirrorDir: t.TempDir()})
		m.activeTab = TabFleet
		m.searching = true
		m.fleet = []apitypes.Job{{ID: 5, Repo: "grafana/mimir", PRNumber: 99, State: "running"}}
		m.history = []apitypes.Job{{ID: 9, Repo: "grafana/loki", PRNumber: 12, State: "done"}}
		return m
	}

	t.Run("typing accumulates and enter jumps", func(t *testing.T) {
		m := seed()
		for _, r := range "loki" {
			next, _ := m.Update(pressRune(r))
			m = next.(Model)
		}
		assert.Equal(t, "loki", m.searchQuery)
		after, _ := m.Update(tea.KeyPressMsg{Text: "enter"})
		am := after.(Model)
		assert.Equal(t, TabHistory, am.activeTab)
		assert.False(t, am.searching)
		assert.Zero(t, am.searchCur)
	})
	t.Run("esc closes and resets state", func(t *testing.T) {
		m := seed()
		m.searchQuery = "lok"
		m.searchCur = 1
		after, _ := m.Update(tea.KeyPressMsg{Text: "esc"})
		am := after.(Model)
		assert.False(t, am.searching)
		assert.Empty(t, am.searchQuery)
		assert.Zero(t, am.searchCur)
	})
	t.Run("enter with an out-of-range cursor closes without panicking", func(t *testing.T) {
		m := seed()
		m.searchQuery = "zzzznope"
		m.searchCur = 5
		after, _ := m.Update(tea.KeyPressMsg{Text: "enter"})
		assert.False(t, after.(Model).searching)
	})
	t.Run("interactive mirror nodes join the union", func(t *testing.T) {
		m := seed()
		m.visible = []tree.Node{{Project: "loki", Worktree: "feature-x"}}
		res := m.searchResults("feature")
		require.NotEmpty(t, res)
		assert.Equal(t, TabInteractive, res[0].tab)
		after := m.gotoResult(res[0])
		assert.Equal(t, TabInteractive, after.activeTab)
		assert.Equal(t, 0, after.cursor)
	})
}

func Test_SearchKeyRouting(t *testing.T) {
	t.Run("? opens search on Fleet", func(t *testing.T) {
		m := New(Deps{MirrorDir: t.TempDir()})
		m.activeTab = TabFleet
		after, _ := m.Update(pressRune('?'))
		am := after.(Model)
		assert.True(t, am.searching)
		assert.False(t, am.showHelp)
	})
	t.Run("? stays help on Interactive", func(t *testing.T) {
		m := New(Deps{MirrorDir: t.TempDir()})
		m.activeTab = TabInteractive
		after, _ := m.Update(pressRune('?'))
		am := after.(Model)
		assert.True(t, am.showHelp)
		assert.False(t, am.searching)
	})
}
