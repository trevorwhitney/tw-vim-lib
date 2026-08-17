package ui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func inboxItems() []apitypes.InboxItem {
	return []apitypes.InboxItem{
		{Escalation: apitypes.Escalation{ID: 10, Kind: "waiting_approval", ActionKind: "merge_pr"},
			Job: apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43}},
	}
}

func inboxModel(t *testing.T, fc *fakeClient) Model {
	fc.inbox = inboxItems()
	m := New(Deps{MirrorDir: t.TempDir(), Client: fc})
	m.inbox = fc.inbox
	m.activeTab = TabInbox
	return m
}

func Test_InboxApproveConfirmation(t *testing.T) {
	t.Run("'a' arms the confirmation instead of resolving", func(t *testing.T) {
		fc := &fakeClient{}
		m := inboxModel(t, fc)
		after, cmd := m.Update(pressRune('a'))
		assert.Nil(t, cmd)
		am := after.(Model)
		assert.True(t, am.prompting)
		assert.Equal(t, promptConfirmApprove, am.promptKind)
		assert.Empty(t, fc.resolves)
		assert.Contains(t, am.promptLabel, "merge_pr")
		assert.Contains(t, am.promptLabel, "grafana/loki#43")
	})

	t.Run("'y' resolves and the ACK reloads", func(t *testing.T) {
		fc := &fakeClient{}
		m := inboxModel(t, fc)
		armed, _ := m.Update(pressRune('a'))
		next, cmd := armed.(Model).Update(pressRune('y'))
		require.NotNil(t, cmd)
		msg := cmd()
		assert.Equal(t, []string{"approve"}, fc.resolves)
		assert.False(t, next.(Model).prompting)
		_, reload := next.(Model).Update(msg)
		assert.NotNil(t, reload)
	})

	for _, key := range []string{"n", "esc", "q"} {
		t.Run(key+" cancels without resolving", func(t *testing.T) {
			fc := &fakeClient{}
			m := inboxModel(t, fc)
			armed, _ := m.Update(pressRune('a'))
			done, cmd := armed.(Model).Update(tea.KeyPressMsg{Text: key})
			assert.Nil(t, cmd)
			assert.False(t, done.(Model).prompting)
			assert.Empty(t, fc.resolves)
			assert.Contains(t, done.(Model).footer, "cancelled")
		})
	}

	t.Run("an unrelated key neither resolves nor cancels", func(t *testing.T) {
		fc := &fakeClient{}
		m := inboxModel(t, fc)
		armed, _ := m.Update(pressRune('a'))
		held, cmd := armed.(Model).Update(pressRune('z'))
		assert.Nil(t, cmd)
		assert.True(t, held.(Model).prompting)
		assert.Empty(t, fc.resolves)
	})

	t.Run("--no-confirm resolves on the first keypress", func(t *testing.T) {
		fc := &fakeClient{inbox: inboxItems()}
		m := New(Deps{MirrorDir: t.TempDir(), Client: fc, NoConfirm: true})
		m.inbox = fc.inbox
		m.activeTab = TabInbox
		_, cmd := m.Update(pressRune('a'))
		require.NotNil(t, cmd)
		cmd()
		assert.Equal(t, []string{"approve"}, fc.resolves)
	})
}

func Test_ApproveConfirmLabel(t *testing.T) {
	t.Run("names the attached action and its PR", func(t *testing.T) {
		assert.Equal(t, "really merge_pr on grafana/loki#43? (y/n)",
			approveConfirmLabel(inboxItems()[0]))
	})
	t.Run("advice-only escalations read as an acknowledgement", func(t *testing.T) {
		it := inboxItems()[0]
		it.Escalation.ActionKind = ""
		assert.Contains(t, approveConfirmLabel(it), "acknowledge advice")
	})
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
