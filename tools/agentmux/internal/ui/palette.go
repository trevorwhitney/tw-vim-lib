package ui

import (
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// command is one palette entry: a label and the action it runs against the model.
type command struct {
	label string
	run   func(Model) (tea.Model, tea.Cmd)
}

// paletteCommands returns the context-aware command set for the current state.
// Tab-switch commands are always present; item actions depend on the active tab
// and selection.
func (m Model) paletteCommands() []command {
	cmds := []command{
		{"Go to Inbox", switchTo(TabInbox)},
		{"Go to Fleet", switchTo(TabFleet)},
		{"Go to Interactive", switchTo(TabInteractive)},
		{"Go to History", switchTo(TabHistory)},
		{"Search (global)", func(mm Model) (tea.Model, tea.Cmd) {
			mm.paletteOpen = false
			mm.searching = true
			mm.searchQuery = ""
			return mm, nil
		}},
	}
	if m.client != nil {
		paused := m.status.Paused
		label := "Pause polling"
		if paused {
			label = "Resume polling"
		}
		cmds = append(cmds,
			command{label, func(mm Model) (tea.Model, tea.Cmd) {
				mm.paletteOpen = false
				return mm, mutate("polling", func() error { return mm.client.SetPolling(!paused) })
			}},
			command{"GC orphaned workspaces", func(mm Model) (tea.Model, tea.Cmd) {
				mm.paletteOpen = false
				return mm, mutate("gc", func() error { return mm.client.GC(0, false) })
			}},
		)
	}
	switch m.activeTab {
	case TabInbox:
		if it, ok := m.currentInbox(); ok && m.client != nil {
			esc := it.Escalation.ID
			job := it.Job.ID
			cmds = append(cmds,
				command{"Approve selected", func(mm Model) (tea.Model, tea.Cmd) {
					mm.paletteOpen = false
					return mm, mutate("approve", func() error { return mm.client.Resolve(esc, "approve", "", "") })
				}},
				command{"Drop in to selected", func(mm Model) (tea.Model, tea.Cmd) {
					mm.paletteOpen = false
					return mm, mutate("drop-in", func() error { return mm.client.DropIn(job) })
				}},
			)
		}
	case TabFleet:
		if j, ok := m.currentFleet(); ok && m.client != nil {
			id := j.ID
			if j.State == "failed" {
				cmds = append(cmds, command{"Retry selected", func(mm Model) (tea.Model, tea.Cmd) {
					mm.paletteOpen = false
					return mm, mutate("retry", func() error { return mm.client.Retry(id) })
				}})
			}
			cmds = append(cmds, command{"Force-remove selected workspace", func(mm Model) (tea.Model, tea.Cmd) {
				mm.paletteOpen = false
				return mm, mutate("gc", func() error { return mm.client.GC(id, true) })
			}})
		}
	}
	return cmds
}

func switchTo(t Tab) func(Model) (tea.Model, tea.Cmd) {
	return func(mm Model) (tea.Model, tea.Cmd) {
		mm.activeTab = t
		mm.paletteOpen = false
		mm.paletteQuery = ""
		return mm, nil
	}
}

func (m Model) paletteVisible() []command {
	return fuzzyFilter(m.paletteQuery, m.paletteCommands(), func(c command) string { return c.label })
}

func (m Model) handlePalette(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.paletteOpen = false
		m.paletteQuery = ""
	case "enter":
		vis := m.paletteVisible()
		if m.paletteCur >= 0 && m.paletteCur < len(vis) {
			return vis[m.paletteCur].run(m)
		}
		m.paletteOpen = false
	case "up":
		if m.paletteCur > 0 {
			m.paletteCur--
		}
	case "down":
		if m.paletteCur < len(m.paletteVisible())-1 {
			m.paletteCur++
		}
	case "backspace":
		if len(m.paletteQuery) > 0 {
			m.paletteQuery = m.paletteQuery[:len(m.paletteQuery)-1]
			m.paletteCur = 0
		}
	default:
		if s := msg.String(); len(s) == 1 {
			m.paletteQuery += s
			m.paletteCur = 0
		}
	}
	return m, nil
}

func (m Model) paletteView() string {
	var b []string
	b = append(b, styleTitle.Render("⌃P "+m.paletteQuery))
	for i, c := range m.paletteVisible() {
		line := c.label
		if i == m.paletteCur {
			line = lipgloss.NewStyle().Reverse(true).Render(line)
		}
		b = append(b, line)
	}
	b = append(b, styleFooter.Render("↑↓ move · ⏎ run · esc close"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}
