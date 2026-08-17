package policy

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/checks"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
)

func depInput(author string, files []string) Input {
	return Input{
		Repo:  "grafana/loki",
		Facts: checks.Facts{PR: github.PR{Number: 42, Author: author, HeadSHA: "abc"}},
		Files: files,
	}
}

func Test_DepUpdates(t *testing.T) {
	p, err := NewDepUpdates(nil)
	require.NoError(t, err)

	t.Run("non-bot author passes through", func(t *testing.T) {
		res, err := p.Evaluate(depInput("alice", []string{"go.mod"}))
		require.NoError(t, err)
		require.Equal(t, Pass, res.Verdict)
	})

	t.Run("bot with allowed files approves and auto-merges", func(t *testing.T) {
		res, err := p.Evaluate(depInput("renovate[bot]",
			[]string{"go.mod", "go.sum", "vendor/github.com/x/y/z.go"}))
		require.NoError(t, err)
		require.Equal(t, Act, res.Verdict)
		require.Equal(t, "approve_and_automerge", res.Action.Kind)
		require.Equal(t, "42", res.Action.Params["number"])
		require.Equal(t, "grafana/loki", res.Action.Params["repo"])
		require.Equal(t, "squash", res.Action.Params["method"])
	})

	t.Run("dependabot is also a dep bot", func(t *testing.T) {
		res, err := p.Evaluate(depInput("dependabot[bot]", []string{"go.sum"}))
		require.NoError(t, err)
		require.Equal(t, Act, res.Verdict)
	})

	t.Run("file outside allowed paths escalates with action attached", func(t *testing.T) {
		res, err := p.Evaluate(depInput("renovate[bot]", []string{"go.mod", "main.go"}))
		require.NoError(t, err)
		require.Equal(t, Escalate, res.Verdict)
		require.Contains(t, res.Question, "main.go")
		require.NotNil(t, res.Action)
	})

	t.Run("truncated file list escalates", func(t *testing.T) {
		in := depInput("renovate[bot]", []string{"go.mod"})
		in.FilesTruncated = true
		res, err := p.Evaluate(in)
		require.NoError(t, err)
		require.Equal(t, Escalate, res.Verdict)
	})
}

func Test_DepUpdates_RejectsInvalidGlob(t *testing.T) {
	_, err := NewDepUpdates(yamlNode(t, `
allowed_paths: ["go.mod", "[bad"]
`))
	require.Error(t, err)
	require.Contains(t, err.Error(), "[bad")
}

func Test_DepUpdates_CustomConfig(t *testing.T) {
	p, err := NewDepUpdates(yamlNode(t, `
allowed_paths: ["package.json", "**/*.lock"]
allowed_authors: ["my-bot"]
merge_method: merge
`))
	require.NoError(t, err)

	res, err := p.Evaluate(depInput("my-bot", []string{"package.json", "sub/dir/yarn.lock"}))
	require.NoError(t, err)
	require.Equal(t, Act, res.Verdict)
	require.Equal(t, "merge", res.Action.Params["method"])

	res, err = p.Evaluate(depInput("my-bot", []string{"go.mod"}))
	require.NoError(t, err)
	require.Equal(t, Escalate, res.Verdict)
}
