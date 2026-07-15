package ui

import (
	"os"
	"path/filepath"
	"time"

	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tmuxjump"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

const refreshInterval = 1500 * time.Millisecond

type refreshMsg struct {
	nodes []tree.Node
	err   error
}
type tickMsg struct{}

// Model is the overview's Bubble Tea model.
type Model struct {
	dir       string
	keys      KeyMap
	nodes     []tree.Node // full tree
	visible   []tree.Node
	collapsed map[string]bool
	cursor    int
	width     int
	height    int
	status    string // footer error/info
	runner    tmuxjump.Runner
	filtering bool   // true while the / filter input is active
	filter    string // current filter query
	showHelp  bool   // true while ? full-help is shown
}

// New builds the model for the given mirror directory.
func New(dir string) Model {
	return Model{
		dir:       dir,
		keys:      DefaultKeyMap(),
		collapsed: map[string]bool{},
		runner:    tmuxjump.ExecRunner{},
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(m.load(), tick())
}

func tick() tea.Cmd {
	return tea.Tick(refreshInterval, func(time.Time) tea.Msg { return tickMsg{} })
}

// load reads the store off the event loop and rebuilds the tree.
func (m Model) load() tea.Cmd {
	dir := m.dir
	return func() tea.Msg {
		now := time.Now().Unix()
		statPath := func(p string) bool { _, err := os.Stat(p); return err == nil }
		mtimeOf := func(p string) int64 {
			if fi, err := os.Stat(p); err == nil {
				return fi.ModTime().Unix()
			}
			return now
		}
		store.Reap(dir, now, statPath, mtimeOf, store.ReapWindowSecs)
		recs, err := store.Load(dir)
		return refreshMsg{nodes: tree.Build(recs, now, statPath), err: err}
	}
}

func (m *Model) rebuildVisible() {
	nodes := m.nodes
	if m.filter != "" {
		nodes = tree.Filter(nodes, m.filter)
	}
	m.visible = tree.Flatten(nodes, m.collapsed)
	if m.cursor >= len(m.visible) {
		m.cursor = len(m.visible) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case tickMsg:
		return m, tea.Batch(m.load(), tick())
	case refreshMsg:
		if msg.err != nil {
			m.status = "load error: " + msg.err.Error()
		} else {
			m.nodes = msg.nodes
			m.status = ""
			m.rebuildVisible()
		}
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	// Filter input mode captures typing until Enter (apply) or Esc (cancel).
	if m.filtering {
		switch msg.String() {
		case "enter":
			m.filtering = false
		case "esc":
			m.filtering = false
			m.filter = ""
			m.rebuildVisible()
		case "backspace":
			if len(m.filter) > 0 {
				m.filter = m.filter[:len(m.filter)-1]
				m.rebuildVisible()
			}
		default:
			if s := msg.String(); len(s) == 1 {
				m.filter += s
				m.rebuildVisible()
			}
		}
		return m, nil
	}

	// Help overlay: any key dismisses it.
	if m.showHelp {
		m.showHelp = false
		return m, nil
	}

	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit
	case key.Matches(msg, m.keys.Down):
		if m.cursor < len(m.visible)-1 {
			m.cursor++
		}
	case key.Matches(msg, m.keys.Up):
		if m.cursor > 0 {
			m.cursor--
		}
	case key.Matches(msg, m.keys.Top):
		m.cursor = 0
	case key.Matches(msg, m.keys.Bottom):
		m.cursor = len(m.visible) - 1
	case key.Matches(msg, m.keys.Toggle):
		m.toggleCollapse()
	case key.Matches(msg, m.keys.Jump):
		return m.jump()
	case key.Matches(msg, m.keys.Purge):
		m.purge()
		return m, m.load()
	case key.Matches(msg, m.keys.Refresh):
		return m, m.load()
	case key.Matches(msg, m.keys.Filter):
		m.filtering = true
	case key.Matches(msg, m.keys.Help):
		m.showHelp = true
	}
	return m, nil
}

func (m *Model) current() (tree.Node, bool) {
	if m.cursor < 0 || m.cursor >= len(m.visible) {
		return tree.Node{}, false
	}
	return m.visible[m.cursor], true
}

func (m *Model) toggleCollapse() {
	n, ok := m.current()
	if !ok {
		return
	}
	var k string
	switch n.Kind {
	case tree.KindProject:
		k = tree.ProjectKey(n.Project)
	case tree.KindWorktree, tree.KindAgent:
		k = tree.WorktreeKey(n.Project, n.Worktree)
	}
	m.collapsed[k] = !m.collapsed[k]
	m.rebuildVisible()
}

func (m Model) jump() (tea.Model, tea.Cmd) {
	n, ok := m.current()
	if !ok {
		return m, nil
	}
	// Resolve the worktree node for the selection: worktree nodes carry
	// Path/Handle directly; agent nodes borrow from their worktree node.
	// Project nodes are not jumpable.
	var wt *tree.Node
	switch n.Kind {
	case tree.KindProject:
		m.status = "select a worktree or agent to jump"
		return m, nil
	case tree.KindWorktree:
		wt = &n
	case tree.KindAgent:
		for i := range m.nodes {
			if m.nodes[i].Kind == tree.KindWorktree &&
				m.nodes[i].Project == n.Project && m.nodes[i].Worktree == n.Worktree {
				wt = &m.nodes[i]
				break
			}
		}
	}
	if wt == nil || wt.Path == "" {
		m.status = "no path for selection"
		return m, nil
	}
	if err := tmuxjump.Jump(wt.Path, wt.Handle, m.runner); err != nil {
		m.status = err.Error()
		return m, nil
	}
	return m, tea.Quit
}

func (m *Model) purge() {
	n, ok := m.current()
	if !ok || n.Kind != tree.KindWorktree || n.Validity != "gone" {
		m.status = "purge: select a removed worktree"
		return
	}
	// Delete every mirror file whose parsed record matches this worktree.
	// Parse-and-compare (not filename prefix matching) so it is symmetric with
	// the producer's percent-encoded worktrees regardless of encoding.
	dir := m.dir
	entries, err := os.ReadDir(dir)
	if err != nil {
		m.status = "purge: " + err.Error()
		return
	}
	var firstRemoveErr error
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".json" {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			continue
		}
		rec, err := store.ParseRecord(data)
		if err != nil {
			continue
		}
		if rec.Project == n.Project && rec.Worktree == n.Worktree {
			if err := os.Remove(filepath.Join(dir, e.Name())); err != nil && firstRemoveErr == nil {
				firstRemoveErr = err
			}
		}
	}
	if firstRemoveErr != nil {
		m.status = "purge: failed to remove: " + firstRemoveErr.Error()
	}
}

func (m Model) View() tea.View {
	content := ""
	if m.showHelp {
		content = helpView()
	} else {
		now := time.Now().Unix()
		var b []string
		title := lipgloss.NewStyle().Bold(true).Render("agentmux — agents across worktrees")
		b = append(b, title)
		if m.filtering || m.filter != "" {
			b = append(b, lipgloss.NewStyle().Faint(true).Render("/"+m.filter))
		}
		for i, n := range m.visible {
			summary := n.Worktree
			row := RenderRow(n, summary, now)
			if i == m.cursor {
				row = lipgloss.NewStyle().Reverse(true).Render(row)
			}
			b = append(b, row)
		}
		if m.status != "" {
			b = append(b, lipgloss.NewStyle().Foreground(lipgloss.Color("1")).Render(m.status))
		}
		b = append(b, lipgloss.NewStyle().Faint(true).Render("⏎ jump · ⇥ collapse · d purge · r refresh · / filter · ? help · q quit"))
		content = lipgloss.JoinVertical(lipgloss.Left, b...)
	}
	v := tea.NewView(content)
	v.AltScreen = true
	return v
}

func helpView() string {
	lines := []string{
		"agentmux — keys",
		"",
		"j/k ↑/↓   move",
		"g/G       first/last",
		"⏎ / o     jump to worktree",
		"⇥ h l     collapse/expand",
		"d         purge a removed (gone) record",
		"r         refresh",
		"/         filter (Enter apply, Esc clear)",
		"?         this help",
		"q / Esc   quit",
		"",
		"(any key to dismiss)",
	}
	return lipgloss.JoinVertical(lipgloss.Left, lines...)
}
