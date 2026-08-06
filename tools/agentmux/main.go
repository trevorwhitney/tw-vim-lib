package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	tea "charm.land/bubbletea/v2"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/socket"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/ui"
)

var _ ui.Client = (*socket.Client)(nil)

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

// agentdSocket resolves agentd's default unix socket path, matching agentd's own
// default resolution (XDG_STATE_HOME else ~/.local/state/agentd).
func agentdSocket() string {
	base := ""
	if x := os.Getenv("XDG_STATE_HOME"); x != "" {
		base = filepath.Join(x, "agentd")
	} else {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".local", "state", "agentd")
	}
	return filepath.Join(base, "agentd.sock")
}

func main() {
	sockPath := flag.String("socket", agentdSocket(), "path to agentd unix socket")
	flag.Parse()

	dir, err := mirrorDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, "agentmux:", err)
		os.Exit(1)
	}

	p := tea.NewProgram(ui.New(ui.Deps{
		MirrorDir: dir,
		Client:    socket.NewClient(*sockPath),
	}))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "agentmux:", err)
		os.Exit(1)
	}
}
