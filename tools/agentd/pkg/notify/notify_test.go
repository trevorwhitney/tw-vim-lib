package notify

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_EscalationCreated_BannerFilter(t *testing.T) {
	for name, tc := range map[string]struct {
		banner string
		kind   string
		want   int
	}{
		"decisions banners input":  {"decisions", "waiting_input", 1},
		"decisions mutes approval": {"decisions", "waiting_approval", 0},
		"all banners approval":     {"all", "waiting_approval", 1},
		"none mutes everything":    {"none", "waiting_input", 0},
	} {
		t.Run(name, func(t *testing.T) {
			n := New(tc.banner, "")
			var got []string
			n.NotifyFn = func(title, message string) error {
				got = append(got, title+": "+message)
				return nil
			}
			n.EscalationCreated(tc.kind, "title", "message")
			require.Len(t, got, tc.want)
		})
	}
}

func Test_New_DefaultsNotifyFn(t *testing.T) {
	n := New("decisions", "")
	require.NotNil(t, n.NotifyFn)
}

func Test_EscalationCreated_NilNotifyFnDoesNotPanic(t *testing.T) {
	n := &Notifier{Banner: "all"}
	n.EscalationCreated("waiting_input", "title", "message")
}

func Test_SetBadge_AtomicWrite(t *testing.T) {
	dir := t.TempDir()
	badge := filepath.Join(dir, "nested", "badge")
	n := New("none", badge)

	require.NoError(t, n.SetBadge(3))
	data, err := os.ReadFile(badge)
	require.NoError(t, err)
	require.Equal(t, "3", string(data))

	require.NoError(t, n.SetBadge(0))
	data, err = os.ReadFile(badge)
	require.NoError(t, err)
	require.Equal(t, "0", string(data))

	_, err = os.Stat(badge + ".tmp")
	require.True(t, os.IsNotExist(err), "tmp file must not linger")
}

func Test_SetBadge_NoFileConfigured(t *testing.T) {
	n := New("none", "")
	require.NoError(t, n.SetBadge(1))
}
