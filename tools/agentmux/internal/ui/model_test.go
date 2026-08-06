package ui

import (
	"errors"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func pressRune(r rune) tea.KeyPressMsg { return tea.KeyPressMsg{Text: string(r)} }

type fakeClient struct {
	inbox   []apitypes.InboxItem
	fleet   []apitypes.Job
	history []apitypes.Job
	detail  apitypes.JobDetail
	status  apitypes.Status
	// read errors (nil = success):
	inboxErr   error
	fleetErr   error
	historyErr error
	detailErr  error
	statusErr  error
	// recorded mutations:
	resolves []string
	dropins  []int64
	retries  []int64
	pollings []bool
	gcs      []int64
}

func (f *fakeClient) Inbox() ([]apitypes.InboxItem, error)        { return f.inbox, f.inboxErr }
func (f *fakeClient) Fleet() ([]apitypes.Job, error)              { return f.fleet, f.fleetErr }
func (f *fakeClient) History(int) ([]apitypes.Job, error)         { return f.history, f.historyErr }
func (f *fakeClient) JobDetail(int64) (apitypes.JobDetail, error) { return f.detail, f.detailErr }
func (f *fakeClient) Status() (apitypes.Status, error)            { return f.status, f.statusErr }
func (f *fakeClient) Resolve(id int64, res, reason, answer string) error {
	f.resolves = append(f.resolves, res)
	return nil
}
func (f *fakeClient) DropIn(id int64) error                { f.dropins = append(f.dropins, id); return nil }
func (f *fakeClient) Handback(int64) error                 { return nil }
func (f *fakeClient) Retry(id int64) error                 { f.retries = append(f.retries, id); return nil }
func (f *fakeClient) SetPolling(p bool) error              { f.pollings = append(f.pollings, p); return nil }
func (f *fakeClient) GC(id int64, force bool) error        { f.gcs = append(f.gcs, id); return nil }
func (f *fakeClient) SetShadow(string, string, bool) error { return nil }

func fleetModel(t *testing.T, fc *fakeClient) Model {
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.activeTab = TabFleet
	m.fleet = []apitypes.Job{{ID: 4, Repo: "grafana/loki", PRNumber: 45, State: "failed"}}
	return m
}

func Test_FleetRetryAndPause(t *testing.T) {
	fc := &fakeClient{}
	m := fleetModel(t, fc)
	t.Run("R retries the selected failed job", func(t *testing.T) {
		_, cmd := m.Update(tea.KeyPressMsg{Text: "R"})
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []int64{4}, fc.retries)
	})
	t.Run("p pauses when currently live", func(t *testing.T) {
		mm := m
		mm.status.Paused = false
		_, cmd := mm.Update(pressRune('p'))
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []bool{true}, fc.pollings)
	})
	t.Run("p resumes when currently paused", func(t *testing.T) {
		fc.pollings = nil
		mm := m
		mm.status.Paused = true
		_, cmd := mm.Update(pressRune('p'))
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []bool{false}, fc.pollings)
	})
	t.Run("d garbage-collects the selected job", func(t *testing.T) {
		_, cmd := m.Update(pressRune('d'))
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []int64{4}, fc.gcs)
	})
	t.Run("i drops in on the selected job", func(t *testing.T) {
		fc.dropins = nil
		_, cmd := m.Update(pressRune('i'))
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []int64{4}, fc.dropins)
	})
	t.Run("view shows header and row", func(t *testing.T) {
		assert.Contains(t, m.fleetView(), "grafana/loki#45")
	})
	t.Run("empty fleet shows placeholder", func(t *testing.T) {
		em := fleetModel(t, fc)
		em.fleet = nil
		assert.Contains(t, em.fleetView(), "fleet empty")
	})
}

func Test_InboxRefreshAndView(t *testing.T) {
	fc := &fakeClient{inbox: []apitypes.InboxItem{
		{Escalation: apitypes.Escalation{ID: 10, Kind: "waiting_approval", Question: "q1"},
			Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43}},
	}}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	cmd := m.loadData()
	require.NotNil(t, cmd)
	msg := cmd()
	m2, _ := m.Update(msg)
	mm := m2.(Model)
	assert.Len(t, mm.inbox, 1)
	assert.Contains(t, mm.inboxView(), "grafana/loki#43")
}

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

func Test_HistoryTab(t *testing.T) {
	fc := &fakeClient{}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.activeTab = TabHistory
	m.history = []apitypes.Job{{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done"}}

	t.Run("enter opens detail", func(t *testing.T) {
		after, _ := m.Update(tea.KeyPressMsg{Text: "enter"})
		assert.True(t, after.(Model).showDetail)
	})
	t.Run("cursor keys do not dismiss detail", func(t *testing.T) {
		mm := m
		mm.showDetail = true
		after, _ := mm.Update(pressRune('j'))
		assert.True(t, after.(Model).showDetail)
	})
	t.Run("esc closes detail", func(t *testing.T) {
		mm := m
		mm.showDetail = true
		after, _ := mm.Update(tea.KeyPressMsg{Text: "esc"})
		assert.False(t, after.(Model).showDetail)
	})
	t.Run("q closes detail", func(t *testing.T) {
		mm := m
		mm.showDetail = true
		after, _ := mm.Update(pressRune('q'))
		assert.False(t, after.(Model).showDetail)
	})
	t.Run("enter on empty history does not open detail", func(t *testing.T) {
		em := m
		em.history = nil
		em.showDetail = false
		after, _ := em.Update(tea.KeyPressMsg{Text: "enter"})
		assert.False(t, after.(Model).showDetail)
	})
	t.Run("empty history shows placeholder", func(t *testing.T) {
		em := m
		em.history = nil
		assert.Contains(t, em.historyView(), "history empty")
	})
}

func Test_LoadData(t *testing.T) {
	t.Run("nil client yields an empty dataMsg", func(t *testing.T) {
		m := New(Deps{MirrorDir: t.TempDir()})
		msg := m.loadData()()
		d, ok := msg.(dataMsg)
		require.True(t, ok)
		assert.Nil(t, d.err)
		assert.Empty(t, d.inbox)
		after, _ := m.Update(d)
		assert.Empty(t, after.(Model).inbox)
	})
	t.Run("a read error short-circuits and surfaces in the footer", func(t *testing.T) {
		fc := &fakeClient{inboxErr: errors.New("socket down")}
		m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
		d := m.loadData()().(dataMsg)
		require.Error(t, d.err)
		after, _ := m.Update(d)
		assert.Contains(t, after.(Model).footer, "load error")
		assert.Contains(t, after.(Model).footer, "socket down")
	})
}

func Test_LoadDetail(t *testing.T) {
	t.Run("nil client yields an empty detailMsg", func(t *testing.T) {
		m := New(Deps{MirrorDir: t.TempDir()})
		msg := m.loadDetail(3)()
		d, ok := msg.(detailMsg)
		require.True(t, ok)
		assert.Nil(t, d.err)
		assert.Zero(t, d.data.job.ID)
	})
	t.Run("populated detail projects into the model", func(t *testing.T) {
		fc := &fakeClient{detail: apitypes.JobDetail{
			Job:       apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done"},
			Decisions: []apitypes.Decision{{Policy: "p", Verdict: "act"}},
		}}
		m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
		msg := m.loadDetail(3)()
		after, _ := m.Update(msg)
		mm := after.(Model)
		assert.Equal(t, int64(3), mm.detail.job.ID)
		require.Len(t, mm.detail.decisions, 1)
		assert.Equal(t, "act", mm.detail.decisions[0].Verdict)
	})
	t.Run("a JobDetail error surfaces in the footer", func(t *testing.T) {
		fc := &fakeClient{detailErr: errors.New("no such job")}
		m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
		msg := m.loadDetail(9)()
		after, _ := m.Update(msg)
		assert.Contains(t, after.(Model).footer, "detail error")
		assert.Contains(t, after.(Model).footer, "no such job")
	})
}
