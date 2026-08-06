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

type promptK int

const (
	promptNone promptK = iota
	promptReject
	promptAnswer
)

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

// a message carrying the loaded detail.
type detailMsg struct {
	data detailData
	err  error
}

// loadDetail fetches one job's full decision chain in a single call off the
// event loop. agentd's /jobs/{id}?detail=1 returns the whole apitypes.JobDetail
// (job + escalation + decisions/actions/events/artifacts), so there is one
// round-trip, not five.
func (m Model) loadDetail(jobID int64) tea.Cmd {
	cl := m.client
	return func() tea.Msg {
		if cl == nil {
			return detailMsg{}
		}
		jd, err := cl.JobDetail(jobID)
		if err != nil {
			return detailMsg{err: err}
		}
		return detailMsg{data: detailData{
			job:        jd.Job,
			escalation: jd.Escalation,
			decisions:  jd.Decisions,
			actions:    jd.Actions,
			events:     jd.Events,
			artifacts:  jd.Artifacts,
		}}
	}
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

	prompting   bool
	promptKind  promptK
	promptValue string
	promptEsc   int64 // escalation id the prompt resolves

	showDetail bool
	detail     detailData

	paletteOpen  bool
	paletteQuery string
	paletteCur   int

	searching   bool
	searchQuery string
	searchCur   int
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
	case mutationDoneMsg:
		if msg.err != nil {
			m.footer = msg.label + ": " + msg.err.Error()
			return m, nil
		}
		m.footer = msg.label + " ✓"
		return m, m.loadData() // re-query immediately on ACK
	case detailMsg:
		if msg.err != nil {
			m.footer = "detail error: " + msg.err.Error()
		} else {
			m.detail = msg.data
		}
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if m.paletteOpen {
		return m.handlePalette(msg)
	}
	if !m.filtering && !m.prompting && !m.searching && !m.showDetail && !m.showHelp &&
		key.Matches(msg, m.keys.Palette) {
		m.paletteOpen = true
		m.paletteQuery = ""
		m.paletteCur = 0
		return m, nil
	}
	if m.searching {
		return m.handleSearch(msg)
	}
	// Interactive tab keeps its own modal filter/help handling.
	if m.activeTab == TabInteractive {
		return m.handleInteractiveKey(msg)
	}
	// Help overlay: any key dismisses it.
	if m.showHelp {
		m.showHelp = false
		return m, nil
	}
	// A prompt is modal: it captures every key until enter/esc.
	if m.prompting {
		return m.handlePrompt(msg)
	}
	// The History detail overlay is modal: it captures every key until esc/q.
	if m.showDetail {
		return m.handleHistoryKey(msg)
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
	switch m.activeTab {
	case TabInbox:
		return m.handleInboxKey(msg)
	case TabFleet:
		return m.handleFleetKey(msg)
	case TabHistory:
		return m.handleHistoryKey(msg)
	}
	return m, nil
}

func (m *Model) currentFleet() (apitypes.Job, bool) {
	if m.fleetCur < 0 || m.fleetCur >= len(m.fleet) {
		return apitypes.Job{}, false
	}
	return m.fleet[m.fleetCur], true
}

func (m Model) handleFleetKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit
	case key.Matches(msg, m.keys.Down):
		if m.fleetCur < len(m.fleet)-1 {
			m.fleetCur++
		}
	case key.Matches(msg, m.keys.Up):
		if m.fleetCur > 0 {
			m.fleetCur--
		}
	case key.Matches(msg, m.keys.Top):
		m.fleetCur = 0
	case key.Matches(msg, m.keys.Bottom):
		m.fleetCur = len(m.fleet) - 1
	case key.Matches(msg, m.keys.RetryJob):
		if j, ok := m.currentFleet(); ok && j.State == "failed" && m.client != nil {
			id := j.ID
			return m, mutate("retry", func() error { return m.client.Retry(id) })
		}
	case key.Matches(msg, m.keys.Dropin):
		if j, ok := m.currentFleet(); ok && m.client != nil {
			id := j.ID
			return m, mutate("drop-in", func() error { return m.client.DropIn(id) })
		}
	case key.Matches(msg, m.keys.Pause):
		if m.client != nil {
			paused := !m.status.Paused
			return m, mutate("polling", func() error { return m.client.SetPolling(paused) })
		}
	case key.Matches(msg, m.keys.GC):
		if j, ok := m.currentFleet(); ok && m.client != nil {
			id := j.ID
			return m, mutate("gc", func() error { return m.client.GC(id, false) })
		}
	case key.Matches(msg, m.keys.OpenPR):
		if j, ok := m.currentFleet(); ok {
			_ = m.runner.OpenURL(prURL(j.Repo, j.PRNumber))
		}
	case key.Matches(msg, m.keys.Search):
		m.searching = true
		m.searchQuery = ""
		m.searchCur = 0
		return m, nil
	case key.Matches(msg, m.keys.Refresh):
		return m, m.loadData()
	case key.Matches(msg, m.keys.Help):
		m.showHelp = true
	}
	return m, nil
}

func (m *Model) currentHistory() (apitypes.Job, bool) {
	if m.historyCur < 0 || m.historyCur >= len(m.history) {
		return apitypes.Job{}, false
	}
	return m.history[m.historyCur], true
}

func (m Model) handleHistoryKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	if m.showDetail {
		switch msg.String() {
		case "esc", "q":
			m.showDetail = false
		}
		return m, nil
	}
	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit
	case key.Matches(msg, m.keys.Down):
		if m.historyCur < len(m.history)-1 {
			m.historyCur++
		}
	case key.Matches(msg, m.keys.Up):
		if m.historyCur > 0 {
			m.historyCur--
		}
	case key.Matches(msg, m.keys.Top):
		m.historyCur = 0
	case key.Matches(msg, m.keys.Bottom):
		m.historyCur = len(m.history) - 1
	case msg.String() == "enter": // enter opens detail (NOT the Jump binding)
		if j, ok := m.currentHistory(); ok {
			m.showDetail = true
			return m, m.loadDetail(j.ID)
		}
	case key.Matches(msg, m.keys.Search):
		m.searching = true
		m.searchQuery = ""
		m.searchCur = 0
		return m, nil
	case key.Matches(msg, m.keys.Refresh):
		return m, m.loadData()
	case key.Matches(msg, m.keys.Help):
		m.showHelp = true
	}
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

func (m *Model) currentInbox() (apitypes.InboxItem, bool) {
	if m.inboxCur < 0 || m.inboxCur >= len(m.inbox) {
		return apitypes.InboxItem{}, false
	}
	return m.inbox[m.inboxCur], true
}

func (m Model) handleInboxKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit
	case key.Matches(msg, m.keys.Down):
		if m.inboxCur < len(m.inbox)-1 {
			m.inboxCur++
		}
	case key.Matches(msg, m.keys.Up):
		if m.inboxCur > 0 {
			m.inboxCur--
		}
	case key.Matches(msg, m.keys.Top):
		m.inboxCur = 0
	case key.Matches(msg, m.keys.Bottom):
		m.inboxCur = len(m.inbox) - 1
	case key.Matches(msg, m.keys.Approve):
		if it, ok := m.currentInbox(); ok && m.client != nil {
			esc := it.Escalation.ID
			return m, mutate("approve", func() error { return m.client.Resolve(esc, "approve", "", "") })
		}
	case key.Matches(msg, m.keys.Reject):
		if it, ok := m.currentInbox(); ok {
			m.prompting, m.promptKind, m.promptValue, m.promptEsc = true, promptReject, "", it.Escalation.ID
		}
	case key.Matches(msg, m.keys.Answer):
		if it, ok := m.currentInbox(); ok {
			m.prompting, m.promptKind, m.promptValue, m.promptEsc = true, promptAnswer, "", it.Escalation.ID
		}
	case key.Matches(msg, m.keys.Dropin):
		if it, ok := m.currentInbox(); ok && m.client != nil {
			id := it.Job.ID
			return m, mutate("drop-in", func() error { return m.client.DropIn(id) })
		}
	case key.Matches(msg, m.keys.OpenPR):
		if it, ok := m.currentInbox(); ok {
			if it.Job.PRNumber == 0 || it.Job.Repo == "" {
				m.footer = "no PR for this item"
				return m, nil
			}
			if err := m.runner.OpenURL(prURL(it.Job.Repo, it.Job.PRNumber)); err != nil {
				m.footer = "open PR: " + err.Error()
			}
		}
	case key.Matches(msg, m.keys.Search):
		m.searching = true
		m.searchQuery = ""
		m.searchCur = 0
		return m, nil
	case key.Matches(msg, m.keys.Refresh):
		return m, m.loadData()
	case key.Matches(msg, m.keys.Help):
		m.showHelp = true
	}
	return m, nil
}

func (m *Model) clearPrompt() {
	m.prompting, m.promptKind, m.promptValue, m.promptEsc = false, promptNone, "", 0
}

func (m Model) handlePrompt(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		esc := m.promptEsc
		val := m.promptValue
		kind := m.promptKind
		m.clearPrompt()
		if m.client == nil {
			return m, nil
		}
		switch kind {
		case promptReject:
			if val == "" {
				m.footer = "reject needs a reason"
				return m, nil
			}
			return m, mutate("reject", func() error { return m.client.Resolve(esc, "reject", val, "") })
		case promptAnswer:
			return m, mutate("answer", func() error { return m.client.Resolve(esc, "answer", "", val) })
		}
	case "esc":
		m.clearPrompt()
	case "backspace":
		if len(m.promptValue) > 0 {
			m.promptValue = m.promptValue[:len(m.promptValue)-1]
		}
	default:
		if s := msg.String(); len(s) == 1 {
			m.promptValue += s
		}
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
	if err := tmuxjump.JumpSession(wt.Path, wt.Handle, m.runner); err != nil {
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
	if m.paletteOpen {
		content = m.paletteView()
	} else if m.searching {
		content = m.searchView()
	} else if m.showHelp {
		content = helpView(m.activeTab)
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
	if m.prompting {
		label := "reason> "
		if m.promptKind == promptAnswer {
			label = "answer> "
		}
		b = append(b, styleFilter.Render(label+m.promptValue))
	}
	if m.footer != "" {
		b = append(b, styleStatus.Render(m.footer))
	}
	b = append(b, styleFooter.Render("a approve · x reject · A answer · i drop-in · o open PR · ↑↓ move · [ ] tabs · ⌃P palette · q quit"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

func (m Model) fleetView() string {
	now := time.Now().Unix()
	var b []string
	for _, line := range fleetHeader(m.status, now) {
		b = append(b, styleSegments(line))
	}
	b = append(b, "")
	if len(m.fleet) == 0 {
		b = append(b, styleFooter.Render("fleet empty — no active jobs"))
	} else {
		for i, j := range m.fleet {
			row := styleSegments(renderFleetRow(j, now))
			if i == m.fleetCur {
				row = lipgloss.NewStyle().Reverse(true).Render(row)
			}
			b = append(b, row)
		}
	}
	if m.footer != "" {
		b = append(b, styleStatus.Render(m.footer))
	}
	b = append(b, styleFooter.Render("R retry · i drop-in · p pause · d gc · o open PR · [ ] tabs · ⌃P palette · q quit"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

func (m Model) historyView() string {
	if m.showDetail {
		return m.detailView() // Batch G
	}
	if len(m.history) == 0 {
		return styleFooter.Render("history empty")
	}
	now := time.Now().Unix()
	var b []string
	for i, j := range m.history {
		row := styleSegments(renderHistoryRow(j, now))
		if i == m.historyCur {
			row = lipgloss.NewStyle().Reverse(true).Render(row)
		}
		b = append(b, row)
	}
	b = append(b, styleFooter.Render("⏎ detail · ↑↓ move · [ ] tabs · ⌃P palette · q quit"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

func (m Model) detailView() string { return renderDetail(m.detail) }

func helpView(active Tab) string {
	global := []string{
		"agentmux mission control — keys",
		"",
		"[ ]        previous / next tab",
		"⌃P         command palette (every action)",
		"?          global search (Inbox/Fleet/History)",
		"j/k ↑/↓    move    g/G first/last    r refresh    q quit",
		"",
	}
	var tab []string
	switch active {
	case TabInbox:
		tab = []string{"Inbox:", "a approve · x reject (reason) · A answer · i drop-in · o open PR"}
	case TabFleet:
		tab = []string{"Fleet:", "R retry · i drop-in · p pause/resume · d gc · o open PR"}
	case TabHistory:
		tab = []string{"History:", "⏎ open decision-chain detail · esc/q close detail"}
	case TabInteractive:
		tab = []string{"Interactive:", "⏎/o jump · ⇥ collapse · d delete record · / filter · ? help"}
	}
	return lipgloss.JoinVertical(lipgloss.Left, append(global, tab...)...)
}
