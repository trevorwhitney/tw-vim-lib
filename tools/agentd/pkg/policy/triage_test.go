package policy

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/classify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/config"
)

func TestConsultTriageAlwaysConsults(t *testing.T) {
	p, err := NewConsultTriage(nil)
	require.NoError(t, err)
	require.Equal(t, "consult-triage", p.Name())

	res, err := p.Evaluate(Input{Repo: "a/b"})
	require.NoError(t, err)
	require.Equal(t, Consult, res.Verdict)
	require.False(t, res.Worktree, "worktree defaults to false")
	require.Equal(t, map[string]VerdictAction{
		"approve":         {Action: "none"},
		"request-changes": {Action: "none"},
		"needs-human":     {Action: "none"},
	}, res.Verdicts, "default verdict set is pure advice")
}

func TestConsultTriageConfig(t *testing.T) {
	var node yaml.Node
	require.NoError(t, yaml.Unmarshal([]byte(`
worktree: true
verdicts:
  approve:
    action: approve_pr
  merge:
    action: merge_pr
    method: rebase
  needs-human:
    action: none
`), &node))
	p, err := NewConsultTriage(node.Content[0])
	require.NoError(t, err)

	res, err := p.Evaluate(Input{Repo: "a/b"})
	require.NoError(t, err)
	require.True(t, res.Worktree)
	require.Equal(t, "approve_pr", res.Verdicts["approve"].Action)
	require.Equal(t, "rebase", res.Verdicts["merge"].Method)
	require.Equal(t, "none", res.Verdicts["needs-human"].Action)
}

func TestConsultTriageRejectsUnknownActions(t *testing.T) {
	var node yaml.Node
	require.NoError(t, yaml.Unmarshal([]byte("verdicts:\n  approve:\n    action: delete_repo\n"), &node))
	_, err := NewConsultTriage(node.Content[0])
	require.Error(t, err)
}

func TestBuildKnowsConsultTriage(t *testing.T) {
	chain, err := Build([]config.PolicyEntry{{Name: "consult-triage"}})
	require.NoError(t, err)
	require.Len(t, chain, 1)
	require.Equal(t, "consult-triage", chain[0].Policy.Name())
}

// classifierProbe pins the convention every classifier-using policy must
// follow: an unavailable classifier falls through to escalate, never to act.
type classifierProbe struct{}

func (classifierProbe) Name() string { return "classifier-probe" }
func (classifierProbe) Evaluate(in Input) (Result, error) {
	if in.Classify == nil {
		return Result{Verdict: Escalate, Question: "classifier not configured", Rationale: "no classifier"}, nil
	}
	res, err := in.Classify(context.Background(), "probe", []string{"yes", "no"})
	if err != nil {
		return Result{Verdict: Escalate, Question: "classifier unavailable", Rationale: err.Error()}, nil
	}
	return Result{Verdict: Act, Rationale: res.Label, Action: &Action{Kind: "approve_pr", Params: map[string]string{}}}, nil
}

func TestClassifierFailureFallsThroughToEscalate(t *testing.T) {
	broken := func(context.Context, string, []string) (classify.Result, error) {
		return classify.Result{}, errors.New("schema violation")
	}
	_, res, _, err := Chain([]WithMeta{{Policy: classifierProbe{}}}, Input{Classify: broken})
	require.NoError(t, err)
	require.Equal(t, Escalate, res.Verdict)

	working := func(context.Context, string, []string) (classify.Result, error) {
		return classify.Result{Label: "yes", Confidence: 1, Reasoning: "r"}, nil
	}
	_, res, _, err = Chain([]WithMeta{{Policy: classifierProbe{}}}, Input{Classify: working})
	require.NoError(t, err)
	require.Equal(t, Act, res.Verdict)
}
