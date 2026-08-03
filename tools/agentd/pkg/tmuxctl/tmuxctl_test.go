package tmuxctl

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

type call struct {
	args []string
	env  map[string]string
}

func fake(responses map[string]string, errs map[string]error) (*[]call, execx.Runner) {
	calls := &[]call{}
	return calls, func(_ context.Context, opts execx.Options, name string, args ...string) (string, error) {
		*calls = append(*calls, call{args: append([]string{name}, args...), env: opts.Env})
		joined := name + " " + strings.Join(args, " ")
		for key, err := range errs {
			if strings.Contains(joined, key) {
				return "", err
			}
		}
		for key, out := range responses {
			if strings.Contains(joined, key) {
				return out, nil
			}
		}
		return "", nil
	}
}

func TestEnsureSessionCreatesWhenMissing(t *testing.T) {
	calls, run := fake(nil, map[string]error{"has-session": errors.New("no session")})
	c := &Client{Exec: run}
	require.NoError(t, c.EnsureSession("agents"))
	require.Equal(t, []string{"tmux", "has-session", "-t", "=agents"}, (*calls)[0].args)
	require.Equal(t, []string{"tmux", "new-session", "-d", "-s", "agents"}, (*calls)[1].args)
}

func TestEnsureSessionNoopWhenPresent(t *testing.T) {
	calls, run := fake(nil, nil)
	c := &Client{Exec: run}
	require.NoError(t, c.EnsureSession("agents"))
	require.Len(t, *calls, 1)
}

func TestNewWindowReturnsID(t *testing.T) {
	calls, run := fake(map[string]string{"new-window": "@42\n"}, nil)
	c := &Client{Exec: run}
	id, err := c.NewWindow("agents", "agentd-7", "/tmp/wt",
		map[string]string{"AGENTD_SESSION_ID": "ses_1"}, `nvim "+AgentFullscreen opencode"`)
	require.NoError(t, err)
	require.Equal(t, "@42", id)
	require.Equal(t, []string{"tmux", "new-window", "-P", "-F", "#{window_id}",
		"-t", "agents:", "-n", "agentd-7", "-c", "/tmp/wt",
		"-e", "AGENTD_SESSION_ID=ses_1",
		`nvim "+AgentFullscreen opencode"`}, (*calls)[0].args)
}

func TestHasWindow(t *testing.T) {
	_, run := fake(map[string]string{"list-windows": "@1\n@42\n@7\n"}, nil)
	c := &Client{Exec: run}
	ok, err := c.HasWindow("@42")
	require.NoError(t, err)
	require.True(t, ok)
	ok, err = c.HasWindow("@99")
	require.NoError(t, err)
	require.False(t, ok)
}

func TestKillWindowIgnoresMissing(t *testing.T) {
	_, run := fake(nil, map[string]error{"kill-window": errors.New("can't find window: @9")})
	c := &Client{Exec: run}
	require.NoError(t, c.KillWindow("@9"))
}
