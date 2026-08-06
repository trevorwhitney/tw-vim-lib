package ui

import "charm.land/bubbles/v2/key"

// KeyMap defines the overview's bindings, mirroring the nvim sidebar vocabulary.
type KeyMap struct {
	Up       key.Binding
	Down     key.Binding
	Top      key.Binding
	Bottom   key.Binding
	Jump     key.Binding
	Toggle   key.Binding
	Purge    key.Binding
	Refresh  key.Binding
	Filter   key.Binding
	Help     key.Binding
	Quit     key.Binding
	NextTab  key.Binding
	PrevTab  key.Binding
	Approve  key.Binding
	Reject   key.Binding
	Answer   key.Binding
	Dropin   key.Binding
	OpenPR   key.Binding
	RetryJob key.Binding
	Pause    key.Binding
	GC       key.Binding
	Palette  key.Binding
	Search   key.Binding
}

// DefaultKeyMap returns the overview's default key bindings.
func DefaultKeyMap() KeyMap {
	return KeyMap{
		Up:       key.NewBinding(key.WithKeys("k", "up"), key.WithHelp("↑/k", "up")),
		Down:     key.NewBinding(key.WithKeys("j", "down"), key.WithHelp("↓/j", "down")),
		Top:      key.NewBinding(key.WithKeys("g"), key.WithHelp("g", "top")),
		Bottom:   key.NewBinding(key.WithKeys("G"), key.WithHelp("G", "bottom")),
		Jump:     key.NewBinding(key.WithKeys("enter", "o"), key.WithHelp("⏎/o", "jump")),
		Toggle:   key.NewBinding(key.WithKeys("tab", "h", "l"), key.WithHelp("⇥", "expand/collapse")),
		Purge:    key.NewBinding(key.WithKeys("d"), key.WithHelp("d", "delete agent/gone worktree record")),
		Refresh:  key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "refresh")),
		Filter:   key.NewBinding(key.WithKeys("/"), key.WithHelp("/", "filter")),
		Help:     key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "help")),
		Quit:     key.NewBinding(key.WithKeys("q", "esc", "ctrl+c"), key.WithHelp("q", "quit")),
		NextTab:  key.NewBinding(key.WithKeys("]"), key.WithHelp("]", "next tab")),
		PrevTab:  key.NewBinding(key.WithKeys("["), key.WithHelp("[", "prev tab")),
		Approve:  key.NewBinding(key.WithKeys("a"), key.WithHelp("a", "approve")),
		Reject:   key.NewBinding(key.WithKeys("x"), key.WithHelp("x", "reject")),
		Answer:   key.NewBinding(key.WithKeys("A"), key.WithHelp("A", "answer")),
		Dropin:   key.NewBinding(key.WithKeys("i"), key.WithHelp("i", "drop-in")),
		OpenPR:   key.NewBinding(key.WithKeys("o"), key.WithHelp("o", "open PR")),
		RetryJob: key.NewBinding(key.WithKeys("R"), key.WithHelp("R", "retry")),
		Pause:    key.NewBinding(key.WithKeys("p"), key.WithHelp("p", "pause/resume polling")),
		GC:       key.NewBinding(key.WithKeys("d"), key.WithHelp("d", "gc workspace")),
		Palette:  key.NewBinding(key.WithKeys("ctrl+p"), key.WithHelp("⌃P", "command palette")),
		Search:   key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "global search")),
	}
}
