package ui

import (
	"os"
	"path/filepath"
	"time"

	"charm.land/bubbles/v2/key"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tmuxjump"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

const refreshInterval = 1500 * time.Millisecond

type refreshMsg struct {
	nodes     []tree.Node
	summaries map[string]string
	err       error
}
type tickMsg struct{}

type dataMsg struct {
	inbox   []apitypes.InboxItem
	fleet   []apitypes.Job
	history []apitypes.Job
	status  apitypes.Status
	err     error
}

// Deps are the model's external collaborators. Client can be nil in tests that
// only exercise the Interactive tab.
type Deps struct {
	MirrorDir string
	Client    Client
	Runner    tmuxjump.Runner
}

// Client reads from and mutates agentd over the socket with apitypes DTOs.
// *socket.Client satisfies it.
type Client interface {
	Inbox() ([]apitypes.InboxItem, error)
	Fleet() ([]apitypes.Job, error)
	History(limit int) ([]apitypes.Job, error)
	JobDetail(id int64) (apitypes.JobDetail, error)
	Status() (apitypes.Status, error)
	Resolve(escalationID int64, resolution, reason, answer string) error
	DropIn(jobID int64) error
	Handback(jobID int64) error
	Retry(jobID int64) error
	SetPolling(paused bool) error
	GC(jobID int64, force bool) error
	SetShadow(repo, policy string, enabled bool) error
}

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
	footer    string // footer error/info
	runner    tmuxjump.Runner
	filtering bool   // true while the / filter input is active
	filter    string // current filter query
	showHelp  bool   // true while ? full-help is shown
	summaries map[string]string

	activeTab Tab
	client    Client
	// Per-tab state for the Inbox, Fleet, and History tabs.
	inbox      []apitypes.InboxItem
	fleet      []apitypes.Job
	history    []apitypes.Job
	status     apitypes.Status // daemon status for Fleet header
	inboxCur   int
	fleetCur   int
	historyCur int
}

// New builds the model for the given deps.
func New(d Deps) Model {
	runner := d.Runner
	if runner == nil {
		runner = tmuxjump.ExecRunner{}
	}
	return Model{
		dir:       d.MirrorDir,
		keys:      DefaultKeyMap(),
		collapsed: map[string]bool{},
		runner:    runner,
		client:    d.Client,
		activeTab: TabInbox,
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(m.load(), m.loadData(), tick())
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

		summaries := map[string]string{}
		if err == nil {
			perProjectDir := map[string]map[string]string{}
			for _, r := range recs {
				projDir := filepath.Dir(r.Path)
				wtmap, ok := perProjectDir[projDir]
				if !ok {
					wtmap = store.LoadWorktreeSummaries(projDir)
					perProjectDir[projDir] = wtmap
				}
				summaries[r.Project+"/"+r.Worktree] = store.Summary(r, wtmap, nil)
			}
		}

		return refreshMsg{nodes: tree.Build(recs, now, statPath), summaries: summaries, err: err}
	}
}

const historyLimit = 200

// loadData reads inbox/fleet/history and daemon status off the event loop. A
// nil client yields an empty dataMsg so the Interactive-only mode still ticks.
func (m Model) loadData() tea.Cmd {
	cl := m.client
	return func() tea.Msg {
		if cl == nil {
			return dataMsg{}
		}
		var d dataMsg
		if d.inbox, d.err = cl.Inbox(); d.err != nil {
			return d
		}
		if d.fleet, d.err = cl.Fleet(); d.err != nil {
			return d
		}
		if d.history, d.err = cl.History(historyLimit); d.err != nil {
			return d
		}
		d.status, _ = cl.Status() // status is best-effort; daemon may be down
		return d
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

func (m *Model) clampCursors() {
	clamp := func(cur, n int) int {
		if cur >= n {
			cur = n - 1
		}
		if cur < 0 {
			cur = 0
		}
		return cur
	}
	m.inboxCur = clamp(m.inboxCur, len(m.inbox))
	m.fleetCur = clamp(m.fleetCur, len(m.fleet))
	m.historyCur = clamp(m.historyCur, len(m.history))
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case tickMsg:
		return m, tea.Batch(m.load(), m.loadData(), tick())
	case refreshMsg:
		if msg.err != nil {
			m.footer = "load error: " + msg.err.Error()
		} else {
			m.nodes = msg.nodes
			m.summaries = msg.summaries
			m.footer = ""
			m.rebuildVisible()
		}
	case dataMsg:
		if msg.err != nil {
			m.footer = "load error: " + msg.err.Error()
		} else {
			m.inbox = msg.inbox
			m.fleet = msg.fleet
			m.history = msg.history
			m.status = msg.status
			m.clampCursors()
		}
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	// Interactive tab keeps its own modal filter/help handling.
	if m.activeTab == TabInteractive {
		return m.handleInteractiveKey(msg)
	}
	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit
	case key.Matches(msg, m.keys.NextTab):
		m.activeTab = m.activeTab.next()
		return m, nil
	case key.Matches(msg, m.keys.PrevTab):
		m.activeTab = m.activeTab.prev()
		return m, nil
	}
	// The Inbox, Fleet, and History tabs have no key bindings yet.
	return m, nil
}

func (m Model) handleInteractiveKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
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
	case key.Matches(msg, m.keys.NextTab):
		m.activeTab = m.activeTab.next()
	case key.Matches(msg, m.keys.PrevTab):
		m.activeTab = m.activeTab.prev()
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
		m.footer = "select a worktree or agent to jump"
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
		m.footer = "no path for selection"
		return m, nil
	}
	if err := tmuxjump.Jump(wt.Path, wt.Handle, m.runner); err != nil {
		m.footer = err.Error()
		return m, nil
	}
	return m, tea.Quit
}

func (m *Model) purge() {
	n, ok := m.current()
	if !ok {
		return
	}
	var match func(store.Record) bool
	switch {
	case n.Kind == tree.KindAgent:
		// Delete just this agent's session record. An agent is uniquely
		// identified by project + worktree + mode + idx.
		r := n.Record
		match = func(rec store.Record) bool {
			return rec.Project == r.Project && rec.Worktree == r.Worktree &&
				rec.Mode == r.Mode && rec.Idx == r.Idx
		}
	case n.Kind == tree.KindWorktree && n.Validity == "gone":
		match = func(rec store.Record) bool {
			return rec.Project == n.Project && rec.Worktree == n.Worktree
		}
	default:
		m.footer = "purge: select a removed worktree or a saved agent"
		return
	}
	if err := m.removeRecords(match); err != nil {
		m.footer = "purge: " + err.Error()
	}
}

// removeRecords deletes every mirror file whose parsed record satisfies match.
// It parses and compares record fields (not filename prefixes) so it stays
// symmetric with the producer's percent-encoded worktrees regardless of
// filename encoding.
func (m *Model) removeRecords(match func(store.Record) bool) error {
	entries, err := os.ReadDir(m.dir)
	if err != nil {
		return err
	}
	var firstRemoveErr error
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".json" {
			continue
		}
		data, err := os.ReadFile(filepath.Join(m.dir, e.Name()))
		if err != nil {
			continue
		}
		rec, err := store.ParseRecord(data)
		if err != nil {
			continue
		}
		if match(rec) {
			if err := os.Remove(filepath.Join(m.dir, e.Name())); err != nil && firstRemoveErr == nil {
				firstRemoveErr = err
			}
		}
	}
	if firstRemoveErr != nil {
		return firstRemoveErr
	}
	return nil
}

func (m Model) View() tea.View {
	var content string
	if m.showHelp {
		content = helpView()
	} else {
		bar := styleSegments(tabBar(m.activeTab, len(m.inbox)))
		var body string
		switch m.activeTab {
		case TabInteractive:
			body = m.interactiveView()
		case TabInbox:
			body = m.inboxView()
		case TabFleet:
			body = m.fleetView()
		case TabHistory:
			body = m.historyView()
		}
		content = lipgloss.JoinVertical(lipgloss.Left, bar, body)
	}
	v := tea.NewView(content)
	v.AltScreen = true
	return v
}

func (m Model) interactiveView() string {
	now := time.Now().Unix()
	var b []string
	b = append(b, styleTitle.Render("agentmux — agents across worktrees"))
	if m.filtering || m.filter != "" {
		b = append(b, styleFilter.Render("/"+m.filter))
	}
	for i, n := range m.visible {
		summary := m.summaries[n.Project+"/"+n.Worktree]
		if summary == "" {
			summary = n.Worktree
		}
		row := styleSegments(RenderRow(n, summary, now))
		if i == m.cursor {
			row = lipgloss.NewStyle().Reverse(true).Render(row)
		}
		b = append(b, row)
	}
	if m.footer != "" {
		b = append(b, styleStatus.Render(m.footer))
	}
	b = append(b, styleFooter.Render("⏎ jump · ⇥ collapse · d delete · r refresh · / filter · ? help · q quit"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

func (m Model) inboxView() string {
	if len(m.inbox) == 0 {
		return styleFooter.Render("inbox empty — nothing waiting")
	}
	now := time.Now().Unix()
	var b []string
	for i, it := range m.inbox {
		row := styleSegments(renderInboxRow(it, now))
		if i == m.inboxCur {
			row = lipgloss.NewStyle().Reverse(true).Render(row)
		}
		b = append(b, row)
	}
	if m.footer != "" {
		b = append(b, styleStatus.Render(m.footer))
	}
	b = append(b, styleFooter.Render("a approve · x reject · A answer · i drop-in · o open PR · ↑↓ move · [ ] tabs · ⌃P palette · q quit"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

func (m Model) fleetView() string   { return styleFooter.Render("(fleet — not yet available)") }
func (m Model) historyView() string { return styleFooter.Render("(history — not yet available)") }

func helpView() string {
	lines := []string{
		"agentmux — keys",
		"",
		"j/k ↑/↓   move",
		"g/G       first/last",
		"⏎ / o     jump to worktree",
		"⇥ h l     collapse/expand",
		"d         delete selected agent, or purge a removed (gone) worktree",
		"r         refresh",
		"/         filter (Enter apply, Esc clear)",
		"?         this help",
		"q / Esc   quit",
		"",
		"(any key to dismiss)",
	}
	return lipgloss.JoinVertical(lipgloss.Left, lines...)
}
