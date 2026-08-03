// Package opencode is the contract for driving the opencode CLI: consult
// sessions, classifier calls, and transcript export. Only CLI knows argv.
package opencode

import (
	"context"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

// Request describes one `opencode run` invocation. Agent and SessionID are
// mutually exclusive; Pure disables external plugins.
type Request struct {
	Dir       string
	Env       map[string]string
	Agent     string
	SessionID string
	Pure      bool
	Prompt    string
}

type Runner interface {
	Run(ctx context.Context, req Request) (string, error)
	// Export returns the session's transcript as JSON.
	Export(ctx context.Context, sessionID string) (string, error)
}

type CLI struct {
	Exec execx.Runner
	Bin  string // defaults to "opencode"
}

var _ Runner = (*CLI)(nil)

func (c *CLI) bin() string {
	if c.Bin != "" {
		return c.Bin
	}
	return "opencode"
}

func (c *CLI) Run(ctx context.Context, req Request) (string, error) {
	args := []string{"run"}
	if req.Pure {
		args = append(args, "--pure")
	}
	if req.Agent != "" {
		args = append(args, "--agent", req.Agent)
	}
	if req.SessionID != "" {
		args = append(args, "--session", req.SessionID)
	}
	args = append(args, req.Prompt)
	return c.Exec(ctx, execx.Options{Dir: req.Dir, Env: req.Env}, c.bin(), args...)
}

func (c *CLI) Export(ctx context.Context, sessionID string) (string, error) {
	return c.Exec(ctx, execx.Options{}, c.bin(), "export", sessionID)
}
