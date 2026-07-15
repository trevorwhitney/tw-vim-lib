package main

import (
	"fmt"
	"os"
	"path/filepath"

	tea "charm.land/bubbletea/v2"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/ui"
)

func mirrorDir() (string, error) {
	if x := os.Getenv("XDG_STATE_HOME"); x != "" {
		return filepath.Join(x, "agentmux", "agents"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home dir: %w", err)
	}
	return filepath.Join(home, ".local", "state", "agentmux", "agents"), nil
}

func main() {
	dir, err := mirrorDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, "agentmux:", err)
		os.Exit(1)
	}
	p := tea.NewProgram(ui.New(dir))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "agentmux:", err)
		os.Exit(1)
	}
}
