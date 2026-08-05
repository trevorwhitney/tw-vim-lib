package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_Tabs(t *testing.T) {
	t.Run("order is Inbox Fleet Interactive History", func(t *testing.T) {
		assert.Equal(t, []Tab{TabInbox, TabFleet, TabInteractive, TabHistory}, allTabs())
	})
	t.Run("names", func(t *testing.T) {
		assert.Equal(t, "Inbox", TabInbox.String())
		assert.Equal(t, "Fleet", TabFleet.String())
		assert.Equal(t, "Interactive", TabInteractive.String())
		assert.Equal(t, "History", TabHistory.String())
		assert.Equal(t, "?", Tab(99).String())
	})
	t.Run("next wraps", func(t *testing.T) {
		assert.Equal(t, TabFleet, TabInbox.next())
		assert.Equal(t, TabInbox, TabHistory.next())
	})
	t.Run("prev wraps", func(t *testing.T) {
		assert.Equal(t, TabHistory, TabInbox.prev())
		assert.Equal(t, TabInbox, TabFleet.prev())
	})
	t.Run("tabBar marks the active tab and shows inbox count", func(t *testing.T) {
		segs := tabBar(TabFleet, 3)
		// The active tab uses RoleTabActive. Other tabs use RoleTabInactive.
		var active string
		for _, s := range segs {
			if s.Role == RoleTabActive {
				active = s.Text
			}
		}
		assert.Contains(t, active, "Fleet")
		// The Inbox label carries its open-escalation count.
		joined := ""
		for _, s := range segs {
			joined += s.Text
		}
		assert.Contains(t, joined, "Inbox (3)")
	})
	t.Run("inactive tabs and separators carry their roles", func(t *testing.T) {
		segs := tabBar(TabFleet, 0)
		assert.Len(t, segs, 7) // 4 labels + 3 separators
		var inactive, seps int
		for _, s := range segs {
			switch s.Role {
			case RoleTabInactive:
				inactive++
			case RoleSep:
				seps++
			}
		}
		assert.Equal(t, 3, inactive)
		assert.Equal(t, 3, seps)
	})
}
