package ui

import (
	"fmt"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// searchResult is one global-search hit and where to jump for it.
type searchResult struct {
	tab   Tab
	index int
	label string
}

// searchResults unions matching rows across Inbox, Fleet, History, and the
// Interactive tree (mirror records) for the given query.
func (m Model) searchResults(query string) []searchResult {
	var out []searchResult
	for i, it := range m.inbox {
		label := fmt.Sprintf("Inbox  %s#%d  %s", it.Job.Repo, it.Job.PRNumber, it.Escalation.Question)
		if fuzzyMatch(query, label) {
			out = append(out, searchResult{TabInbox, i, label})
		}
	}
	for i, j := range m.fleet {
		label := fmt.Sprintf("Fleet  %s#%d  %s", j.Repo, j.PRNumber, j.State)
		if fuzzyMatch(query, label) {
			out = append(out, searchResult{TabFleet, i, label})
		}
	}
	for i, j := range m.history {
		label := fmt.Sprintf("History  %s#%d  %s", j.Repo, j.PRNumber, j.Outcome)
		if fuzzyMatch(query, label) {
			out = append(out, searchResult{TabHistory, i, label})
		}
	}
	for i, n := range m.visible { // mirror records shown in the Interactive tree
		label := "Interactive  " + n.Project + "/" + n.Worktree
		if fuzzyMatch(query, label) {
			out = append(out, searchResult{TabInteractive, i, label})
		}
	}
	return out
}

// gotoResult jumps to the result's tab and positions the matching cursor.
func (m Model) gotoResult(r searchResult) Model {
	m.searching = false
	m.searchQuery = ""
	m.searchCur = 0
	m.activeTab = r.tab
	switch r.tab {
	case TabInbox:
		m.inboxCur = r.index
	case TabFleet:
		m.fleetCur = r.index
	case TabHistory:
		m.historyCur = r.index
	case TabInteractive:
		m.cursor = r.index
	}
	return m
}

func (m Model) handleSearch(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.searching = false
		m.searchQuery = ""
		m.searchCur = 0
	case "enter":
		res := m.searchResults(m.searchQuery)
		if m.searchCur >= 0 && m.searchCur < len(res) {
			return m.gotoResult(res[m.searchCur]), nil
		}
		m.searching = false
	case "up":
		if m.searchCur > 0 {
			m.searchCur--
		}
	case "down":
		if m.searchCur < len(m.searchResults(m.searchQuery))-1 {
			m.searchCur++
		}
	case "backspace":
		if len(m.searchQuery) > 0 {
			m.searchQuery = m.searchQuery[:len(m.searchQuery)-1]
			m.searchCur = 0
		}
	default:
		if s := msg.String(); len(s) == 1 {
			m.searchQuery += s
			m.searchCur = 0
		}
	}
	return m, nil
}

func (m Model) searchView() string {
	var b []string
	b = append(b, styleTitle.Render("? "+m.searchQuery))
	for i, r := range m.searchResults(m.searchQuery) {
		line := r.label
		if i == m.searchCur {
			line = lipgloss.NewStyle().Reverse(true).Render(line)
		}
		b = append(b, line)
	}
	b = append(b, styleFooter.Render("↑↓ move · ⏎ go · esc close"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}
