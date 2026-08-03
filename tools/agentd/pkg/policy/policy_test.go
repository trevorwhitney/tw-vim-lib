package policy

import (
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/config"
)

type fake struct {
	name string
	res  Result
}

func (f fake) Name() string                   { return f.name }
func (f fake) Evaluate(Input) (Result, error) { return f.res, nil }

func Test_Chain_FirstMatchWins(t *testing.T) {
	chain := []WithMeta{
		{Policy: fake{name: "first", res: Result{Verdict: Pass, Rationale: "n/a"}}},
		{Policy: fake{name: "second", res: Result{Verdict: Act, Action: &Action{Kind: "merge_pr"}}}},
		{Policy: fake{name: "third", res: Result{Verdict: Escalate}}},
	}
	idx, res, trail, err := Chain(chain, Input{})
	require.NoError(t, err)
	require.Equal(t, 1, idx)
	require.Equal(t, Act, res.Verdict)
	require.Len(t, trail, 2, "third policy must not be evaluated")
	require.Equal(t, "first", trail[0].Policy)
	require.Equal(t, "second", trail[1].Policy)
}

func Test_Chain_AllPass(t *testing.T) {
	chain := []WithMeta{{Policy: fake{name: "only", res: Result{Verdict: Pass}}}}
	idx, res, trail, err := Chain(chain, Input{})
	require.NoError(t, err)
	require.Equal(t, -1, idx)
	require.Equal(t, Pass, res.Verdict)
	require.Len(t, trail, 1)
}

func yamlNode(t *testing.T, src string) *yaml.Node {
	t.Helper()
	var doc yaml.Node
	require.NoError(t, yaml.Unmarshal([]byte(src), &doc))
	return doc.Content[0]
}

func Test_Build_KnownPolicyAndShadow(t *testing.T) {
	entries := []config.PolicyEntry{{
		Name: "merge-dependency-updates",
		Raw:  yamlNode(t, "shadow: true\nallowed_paths: [\"go.mod\"]\n"),
	}}
	chain, err := Build(entries)
	require.NoError(t, err)
	require.Len(t, chain, 1)
	require.True(t, chain[0].Shadow)
	require.Equal(t, "merge-dependency-updates", chain[0].Policy.Name())
}

func Test_Build_UnknownPolicy(t *testing.T) {
	_, err := Build([]config.PolicyEntry{{Name: "nope"}})
	require.ErrorContains(t, err, "unknown policy")
}
