package tmuxjump

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeRunner struct {
	panes        string // list-panes output
	panesAfter   string // list-panes output after a workmux open
	listErr      error  // error on first ListPanes
	listAfterErr error  // error on ListPanes after WorkmuxOpen
	opened       bool
	selected     string // window id passed to select-window
	selectErr    error  // error on SelectWindow
	openErr      error
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
