package opencode

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

func record(out string) (*[][]string, *[]execx.Options, execx.Runner) {
	calls := &[][]string{}
	opts := &[]execx.Options{}
	return calls, opts, func(_ context.Context, o execx.Options, name string, args ...string) (string, error) {
		*calls = append(*calls, append([]string{name}, args...))
		*opts = append(*opts, o)
		return out, nil
	}
}

func TestRunAgent(t *testing.T) {
	calls, opts, exec := record("ok")
	c := &CLI{Exec: exec}
	out, err := c.Run(context.Background(), Request{
		Dir:    "/tmp/wt",
		Env:    map[string]string{"AGENTD_JOB_TOKEN": "7"},
		Agent:  "consult",
		Prompt: "analyze this",
	})
	require.NoError(t, err)
	require.Equal(t, "ok", out)
	require.Equal(t, [][]string{{"opencode", "run", "--dir", "/tmp/wt", "--agent", "consult", "analyze this"}}, *calls)
	require.Equal(t, "/tmp/wt", (*opts)[0].Dir)
	require.Equal(t, "7", (*opts)[0].Env["AGENTD_JOB_TOKEN"])
}

func TestRunSessionAndPure(t *testing.T) {
	calls, _, exec := record("ok")
	c := &CLI{Exec: exec, Bin: "/x/fake-opencode"}
	_, err := c.Run(context.Background(), Request{SessionID: "ses_1", Prompt: "continue"})
	require.NoError(t, err)
	_, err = c.Run(context.Background(), Request{Pure: true, Prompt: "classify"})
	require.NoError(t, err)
	require.Equal(t, [][]string{
		{"/x/fake-opencode", "run", "--session", "ses_1", "continue"},
		{"/x/fake-opencode", "run", "--pure", "classify"},
	}, *calls)
}

func TestExport(t *testing.T) {
	calls, _, exec := record(`{"messages":[]}`)
	c := &CLI{Exec: exec}
	out, err := c.Export(context.Background(), "ses_1")
	require.NoError(t, err)
	require.Equal(t, `{"messages":[]}`, out)
	require.Equal(t, [][]string{{"opencode", "export", "ses_1"}}, *calls)
}
