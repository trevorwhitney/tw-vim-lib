package ui

import "charm.land/bubbles/v2/key"

// KeyMap defines the overview's bindings, mirroring the nvim sidebar vocabulary.
type KeyMap struct {
	Up      key.Binding
	Down    key.Binding
	Top     key.Binding
	Bottom  key.Binding
	Jump    key.Binding
	Toggle  key.Binding
	Purge   key.Binding
	Refresh key.Binding
	Filter  key.Binding
	Help    key.Binding
	Quit    key.Binding
}

// DefaultKeyMap returns the overview's default key bindings.
func DefaultKeyMap() KeyMap {
	return KeyMap{
		Up:      key.NewBinding(key.WithKeys("k", "up"), key.WithHelp("↑/k", "up")),
		Down:    key.NewBinding(key.WithKeys("j", "down"), key.WithHelp("↓/j", "down")),
		Top:     key.NewBinding(key.WithKeys("g"), key.WithHelp("g", "top")),
		Bottom:  key.NewBinding(key.WithKeys("G"), key.WithHelp("G", "bottom")),
		Jump:    key.NewBinding(key.WithKeys("enter", "o"), key.WithHelp("⏎/o", "jump")),
		Toggle:  key.NewBinding(key.WithKeys("tab", "h", "l"), key.WithHelp("⇥", "expand/collapse")),
		Purge:   key.NewBinding(key.WithKeys("d"), key.WithHelp("d", "purge gone record")),
		Refresh: key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "refresh")),
		Filter:  key.NewBinding(key.WithKeys("/"), key.WithHelp("/", "filter")),
		Help:    key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "help")),
		Quit:    key.NewBinding(key.WithKeys("q", "esc", "ctrl+c"), key.WithHelp("q", "quit")),
	}
}
