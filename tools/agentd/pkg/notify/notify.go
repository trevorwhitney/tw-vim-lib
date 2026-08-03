// Package notify delivers escalation banners to the desktop notification
// center and maintains the badge count file consumed by the tmux status line.
package notify

import (
	"os"
	"path/filepath"
	"strconv"

	"github.com/gen2brain/beeep"
)

type Notifier struct {
	Banner    string // decisions | all | none
	BadgeFile string
	// NotifyFn delivers one banner. Defaults to beeep; tests inject a
	// recorder.
	NotifyFn func(title, message string) error
}

func New(banner, badgeFile string) *Notifier {
	return &Notifier{
		Banner:    banner,
		BadgeFile: badgeFile,
		NotifyFn: func(title, message string) error {
			return beeep.Notify(title, message, "")
		},
	}
}

// EscalationCreated emits a banner when the configured filter allows it.
// Delivery failures are ignored: notifications are best-effort.
func (n *Notifier) EscalationCreated(kind, title, message string) {
	switch n.Banner {
	case "none":
		return
	case "decisions":
		if kind != "waiting_input" {
			return
		}
	}
	if n.NotifyFn == nil {
		return
	}
	_ = n.NotifyFn(title, message)
}

// SetBadge atomically replaces the badge file contents with count.
func (n *Notifier) SetBadge(count int) error {
	if n.BadgeFile == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(n.BadgeFile), 0o755); err != nil {
		return err
	}
	tmp := n.BadgeFile + ".tmp"
	if err := os.WriteFile(tmp, []byte(strconv.Itoa(count)), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, n.BadgeFile)
}
