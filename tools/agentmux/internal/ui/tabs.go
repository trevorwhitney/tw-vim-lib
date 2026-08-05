package ui

import "fmt"

// Tab identifies a top-level mission-control view.
type Tab int

const (
	TabInbox Tab = iota
	TabFleet
	TabInteractive
	TabHistory
)

func allTabs() []Tab { return []Tab{TabInbox, TabFleet, TabInteractive, TabHistory} }

func (t Tab) String() string {
	switch t {
	case TabInbox:
		return "Inbox"
	case TabFleet:
		return "Fleet"
	case TabInteractive:
		return "Interactive"
	case TabHistory:
		return "History"
	}
	return "?"
}

func (t Tab) next() Tab { return Tab((int(t) + 1) % len(allTabs())) }
func (t Tab) prev() Tab { return Tab((int(t) + len(allTabs()) - 1) % len(allTabs())) }

// tabBar returns the styled tab-bar segments. The active tab is bold. The Inbox
// label carries the live open-escalation count.
func tabBar(active Tab, inboxCount int) []Segment {
	tabs := allTabs()
	var segs []Segment
	for i, t := range tabs {
		label := t.String()
		if t == TabInbox {
			label = fmt.Sprintf("Inbox (%d)", inboxCount)
		}
		role := RoleTabInactive
		if t == active {
			role = RoleTabActive
		}
		segs = append(segs, Segment{Text: label, Role: role})
		if i < len(tabs)-1 {
			segs = append(segs, Segment{Text: "  ", Role: RoleSep})
		}
	}
	return segs
}
