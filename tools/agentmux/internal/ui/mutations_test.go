package ui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func inboxModel(t *testing.T, fc *fakeClient) Model {
	fc.inbox = []apitypes.InboxItem{
		{Escalation: apitypes.Escalation{ID: 10, Kind: "waiting_approval"},
			Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43}},
	}
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.inbox = fc.inbox
	m.activeTab = TabInbox
	return m
}

func Test_InboxApprove(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	next, cmd := m.Update(pressRune('a'))
	require.NotNil(t, cmd)
	msg := cmd() // runs the resolve
	assert.Equal(t, []string{"approve"}, fc.resolves)
	// The ACK message triggers a reload command.
	_, reload := next.(Model).Update(msg)
	assert.NotNil(t, reload)
}

func Test_InboxRejectPromptsForReason(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	after, _ := m.Update(pressRune('x'))
	am := after.(Model)
	assert.True(t, am.prompting)
	assert.Equal(t, promptReject, am.promptKind)
	// Type a reason and submit.
	am.promptValue = "not now"
	done, cmd := am.Update(tea.KeyPressMsg{Text: "enter"})
	require.NotNil(t, cmd)
	cmd()
	assert.Equal(t, []string{"reject"}, fc.resolves)
	assert.False(t, done.(Model).prompting)
}

func Test_InboxDropIn(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	_, cmd := m.Update(pressRune('i'))
	require.NotNil(t, cmd)
	cmd()
	assert.Equal(t, []int64{2}, fc.dropins)
}

func Test_InboxRejectNeedsReason(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	after, _ := m.Update(pressRune('x'))
	am := after.(Model)
	require.True(t, am.prompting)
	// Submitting an empty reason must not resolve; it reports the requirement.
	done, cmd := am.Update(tea.KeyPressMsg{Text: "enter"})
	assert.Nil(t, cmd)
	assert.Empty(t, fc.resolves)
	assert.Contains(t, done.(Model).footer, "reason")
}

func Test_InboxPromptEscCancels(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	after, _ := m.Update(pressRune('x'))
	require.True(t, after.(Model).prompting)
	done, cmd := after.(Model).Update(tea.KeyPressMsg{Text: "esc"})
	assert.Nil(t, cmd)
	assert.False(t, done.(Model).prompting)
	assert.Empty(t, fc.resolves)
}

func Test_InboxPromptCapturesTyping(t *testing.T) {
	fc := &fakeClient{}
	m := inboxModel(t, fc)
	after, _ := m.Update(pressRune('x'))
	am := after.(Model)
	// Typing accumulates into promptValue, including a literal 'q'.
	for _, r := range "queue" {
		next, _ := am.Update(pressRune(r))
		am = next.(Model)
	}
	assert.Equal(t, "queue", am.promptValue)
	assert.True(t, am.prompting) // typing 'q' must NOT quit
}
