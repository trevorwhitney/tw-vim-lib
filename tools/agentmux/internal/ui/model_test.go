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
	statusErr  error
	// recorded mutations:
	resolves []string
	dropins  []int64
	retries  []int64
}

func (f *fakeClient) Inbox() ([]apitypes.InboxItem, error)        { return f.inbox, f.inboxErr }
func (f *fakeClient) Fleet() ([]apitypes.Job, error)              { return f.fleet, f.fleetErr }
func (f *fakeClient) History(int) ([]apitypes.Job, error)         { return f.history, f.historyErr }
func (f *fakeClient) JobDetail(int64) (apitypes.JobDetail, error) { return f.detail, nil }
func (f *fakeClient) Status() (apitypes.Status, error)            { return f.status, f.statusErr }
func (f *fakeClient) Resolve(id int64, res, reason, answer string) error {
	f.resolves = append(f.resolves, res)
	return nil
}
func (f *fakeClient) DropIn(id int64) error                { f.dropins = append(f.dropins, id); return nil }
func (f *fakeClient) Handback(int64) error                 { return nil }
func (f *fakeClient) Retry(id int64) error                 { f.retries = append(f.retries, id); return nil }
func (f *fakeClient) SetPolling(bool) error                { return nil }
func (f *fakeClient) GC(int64, bool) error                 { return nil }
func (f *fakeClient) SetShadow(string, string, bool) error { return nil }

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
