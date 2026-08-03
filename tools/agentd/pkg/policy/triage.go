package policy

import (
	"fmt"

	"gopkg.in/yaml.v3"
)

// ConsultTriage hands every PR that reaches it to an advise-only consult
// session. It is terminal: place it last in a chain. Verdicts declares the
// labels the consultant may report and what operator approval executes for
// each; the default set is pure advice (every verdict maps to none).
type ConsultTriage struct {
	Worktree bool                     `yaml:"worktree"`
	Verdicts map[string]VerdictAction `yaml:"verdicts"`
}

func NewConsultTriage(raw *yaml.Node) (*ConsultTriage, error) {
	p := &ConsultTriage{}
	if raw != nil {
		if err := raw.Decode(p); err != nil {
			return nil, err
		}
	}
	if len(p.Verdicts) == 0 {
		p.Verdicts = map[string]VerdictAction{
			"approve":         {Action: "none"},
			"request-changes": {Action: "none"},
			"needs-human":     {Action: "none"},
		}
	}
	for verdict, va := range p.Verdicts {
		switch va.Action {
		case "", "none":
			va.Action = "none"
			p.Verdicts[verdict] = va
		case "approve_pr", "merge_pr", "comment_pr":
		default:
			return nil, fmt.Errorf("consult-triage verdict %q: action must be approve_pr|merge_pr|comment_pr|none, got %q", verdict, va.Action)
		}
	}
	return p, nil
}

func (p *ConsultTriage) Name() string { return "consult-triage" }

func (p *ConsultTriage) Evaluate(in Input) (Result, error) {
	return Result{
		Verdict:   Consult,
		Rationale: "triage consult requested for every eligible PR",
		Worktree:  p.Worktree,
		Verdicts:  p.Verdicts,
	}, nil
}
