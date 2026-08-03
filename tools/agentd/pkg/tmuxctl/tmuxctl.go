// Package tmuxctl is the contract for driving tmux: a dedicated background
// session, one window per drop-in, existence checks for window-close
// detection. Only Client knows tmux argv.
package tmuxctl

import (
	"context"
	"sort"
	"strings"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

// Tmux is the surface consumers depend on.
type Tmux interface {
	// EnsureSession creates the detached session when it does not exist.
	EnsureSession(name string) error
	// NewWindow opens a window in session running command with cwd dir and
	// the given extra environment, returning the stable tmux window id
	// (e.g. "@42").
	NewWindow(session, name, dir string, env map[string]string, command string) (string, error)
	HasWindow(windowID string) (bool, error)
	// KillWindow closes the window; a window that is already gone is not an
	// error.
	KillWindow(windowID string) error
}

// Client implements Tmux against the tmux binary. SocketName, when set, uses
// an isolated tmux server (tmux -L).
type Client struct {
	Exec       execx.Runner
	SocketName string
}

var _ Tmux = (*Client)(nil)

func (c *Client) tmux(ctx context.Context, args ...string) (string, error) {
	if c.SocketName != "" {
		args = append([]string{"-L", c.SocketName}, args...)
	}
	return c.Exec(ctx, execx.Options{}, "tmux", args...)
}

func (c *Client) EnsureSession(name string) (err error) {
	ctx := context.Background()
	if _, err = c.tmux(ctx, "has-session", "-t", "="+name); err == nil {
		return nil
	}
	_, err = c.tmux(ctx, "new-session", "-d", "-s", name)
	return err
}

func (c *Client) NewWindow(session, name, dir string, env map[string]string, command string) (string, error) {
	args := []string{"new-window", "-P", "-F", "#{window_id}", "-t", session + ":", "-n", name, "-c", dir}
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		args = append(args, "-e", k+"="+env[k])
	}
	args = append(args, command)
	out, err := c.tmux(context.Background(), args...)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func (c *Client) HasWindow(windowID string) (bool, error) {
	out, err := c.tmux(context.Background(), "list-windows", "-a", "-F", "#{window_id}")
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(out, "\n") {
		if strings.TrimSpace(line) == windowID {
			return true, nil
		}
	}
	return false, nil
}

func (c *Client) KillWindow(windowID string) error {
	_, err := c.tmux(context.Background(), "kill-window", "-t", windowID)
	if err != nil && strings.Contains(err.Error(), "can't find window") {
		return nil
	}
	return err
}
