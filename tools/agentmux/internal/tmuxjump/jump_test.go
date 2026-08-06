package tmuxjump

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeRunner struct {
	panes           string // list-panes output
	panesAfter      string // list-panes output after a workmux open
	listErr         error  // error on first ListPanes
	listAfterErr    error  // error on ListPanes after WorkmuxOpen
	opened          bool
	selected        string // window id passed to select-window
	selectErr       error  // error on SelectWindow
	openErr         error
	switchedSession string // session passed to SwitchClient
}

func (f *fakeRunner) ListPanes() (string, error) {
	if f.opened {
		return f.panesAfter, f.listAfterErr
	}
	return f.panes, f.listErr
}
func (f *fakeRunner) SelectWindow(id string) error {
	f.selected = id
	return f.selectErr
}
func (f *fakeRunner) WorkmuxOpen(handle string) error {
	if f.openErr != nil {
		return f.openErr
	}
	f.opened = true
	return nil
}
func (f *fakeRunner) OpenURL(string) error { return nil }
func (f *fakeRunner) ListPanesSession() (string, error) {
	if f.opened {
		return f.panesAfter, f.listAfterErr
	}
	return f.panes, f.listErr
}
func (f *fakeRunner) SwitchClient(s string) error { f.switchedSession = s; return nil }

func Test_Jump(t *testing.T) {
	t.Run("selects the window whose pane path matches exactly", func(t *testing.T) {
		r := &fakeRunner{panes: "@3 /w/loki/wt\n@5 /w/other/x\n"}
		err := Jump("/w/loki/wt", "wt", r)
		require.NoError(t, err)
		assert.Equal(t, "@3", r.selected)
	})

	t.Run("matches a pane cd'd into a subdirectory", func(t *testing.T) {
		r := &fakeRunner{panes: "@7 /w/loki/wt/src/pkg\n"}
		err := Jump("/w/loki/wt", "wt", r)
		require.NoError(t, err)
		assert.Equal(t, "@7", r.selected)
	})

	t.Run("first match wins when multiple", func(t *testing.T) {
		r := &fakeRunner{panes: "@1 /w/loki/wt\n@2 /w/loki/wt\n"}
		err := Jump("/w/loki/wt", "wt", r)
		require.NoError(t, err)
		assert.Equal(t, "@1", r.selected)
	})

	t.Run("no match triggers workmux open then re-resolves", func(t *testing.T) {
		r := &fakeRunner{panes: "", panesAfter: "@9 /w/loki/wt\n"}
		err := Jump("/w/loki/wt", "wt", r)
		require.NoError(t, err)
		assert.True(t, r.opened)
		assert.Equal(t, "@9", r.selected)
	})

	t.Run("both fail returns error", func(t *testing.T) {
		r := &fakeRunner{panes: "", openErr: errors.New("no workmux")}
		err := Jump("/w/loki/wt", "wt", r)
		assert.Error(t, err)
	})

	t.Run("first list error still tries workmux open and surfaces on total failure", func(t *testing.T) {
		r := &fakeRunner{listErr: errors.New("no server"), openErr: errors.New("no workmux")}
		err := Jump("/w/loki/wt", "wt", r)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "wt")
	})

	t.Run("select error is surfaced", func(t *testing.T) {
		r := &fakeRunner{panes: "@3 /w/loki/wt\n", selectErr: errors.New("bad target")}
		err := Jump("/w/loki/wt", "wt", r)
		require.Error(t, err)
	})
}

func Test_JumpCrossSession(t *testing.T) {
	t.Run("switches to the owning session then selects the window", func(t *testing.T) {
		// list-panes -a includes a session column now: "<session> <window_id> <path>".
		fr := &fakeRunner{
			panes: "agents @7 /Users/me/.local/state/agentd/worktrees/loki/42\n" +
				"main @2 /Users/me/workspace/loki/feature",
		}
		err := JumpSession("/Users/me/.local/state/agentd/worktrees/loki/42", "", fr)
		require.NoError(t, err)
		assert.Equal(t, "agents", fr.switchedSession)
		assert.Equal(t, "@7", fr.selected) // JumpSession calls SelectWindow, which sets f.selected
	})
	t.Run("falls back to workmux open and re-resolves", func(t *testing.T) {
		fr := &fakeRunner{
			panes:      "main @2 /w/other/x\n",
			panesAfter: "agents @9 /w/loki/wt\n",
		}
		err := JumpSession("/w/loki/wt", "wt", fr)
		require.NoError(t, err)
		assert.True(t, fr.opened)
		assert.Equal(t, "agents", fr.switchedSession)
		assert.Equal(t, "@9", fr.selected)
	})
	t.Run("errors when no window exists and no handle to open", func(t *testing.T) {
		fr := &fakeRunner{panes: "main @2 /w/other/x\n"}
		err := JumpSession("/w/loki/wt", "", fr)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "/w/loki/wt")
	})
	t.Run("initial list error still tries the workmux fallback", func(t *testing.T) {
		fr := &fakeRunner{
			listErr:    errors.New("no server"),
			panesAfter: "agents @9 /w/loki/wt\n",
		}
		err := JumpSession("/w/loki/wt", "wt", fr)
		require.NoError(t, err)
		assert.True(t, fr.opened)
		assert.Equal(t, "@9", fr.selected)
	})
	t.Run("initial list error without a handle is fatal", func(t *testing.T) {
		fr := &fakeRunner{listErr: errors.New("no server")}
		err := JumpSession("/w/loki/wt", "", fr)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "no server")
	})
}
