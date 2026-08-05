package ui

import (
	"fmt"

	tea "charm.land/bubbletea/v2"
)

// mutationDoneMsg reports a socket mutation finished; err is non-nil on failure.
// The model responds by reloading over the socket (read-your-writes via ACK).
type mutationDoneMsg struct {
	label string
	err   error
}

// mutate wraps a socket call as a command emitting mutationDoneMsg.
func mutate(label string, fn func() error) tea.Cmd {
	return func() tea.Msg { return mutationDoneMsg{label: label, err: fn()} }
}

func prURL(repo string, pr int) string {
	return fmt.Sprintf("https://github.com/%s/pull/%d", repo, pr)
}
