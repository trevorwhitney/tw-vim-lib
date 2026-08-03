// Package policy defines the deterministic policy chain: verdict types, the
// first-match evaluator, and the registry mapping config names to
// implementations.
package policy

import (
	"fmt"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/checks"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/config"
)

type Verdict string

const (
	Pass     Verdict = "pass"
	Act      Verdict = "act"
	Escalate Verdict = "escalate"
)

// Action is a write the daemon may execute on the PR.
type Action struct {
	Kind   string            `json:"kind"`
	Params map[string]string `json:"params"`
}

type Result struct {
	Verdict   Verdict
	Rationale string
	Action    *Action
	Question  string
}

type Input struct {
	Repo           string
	Facts          checks.Facts
	Files          []string
	FilesTruncated bool
}

type Policy interface {
	Name() string
	Evaluate(in Input) (Result, error)
}

type WithMeta struct {
	Policy Policy
	Shadow bool
}

type Evaluated struct {
	Policy    string
	Verdict   Verdict
	Rationale string
}

// Chain evaluates policies in order; the first non-Pass result handles the
// input. idx is the handling policy's position, -1 when every policy passed.
// trail records every evaluation made, in order.
func Chain(policies []WithMeta, in Input) (idx int, res Result, trail []Evaluated, err error) {
	for i, p := range policies {
		r, err := p.Policy.Evaluate(in)
		if err != nil {
			return -1, Result{}, trail, fmt.Errorf("policy %s: %w", p.Policy.Name(), err)
		}
		trail = append(trail, Evaluated{Policy: p.Policy.Name(), Verdict: r.Verdict, Rationale: r.Rationale})
		if r.Verdict != Pass {
			return i, r, trail, nil
		}
	}
	return -1, Result{Verdict: Pass}, trail, nil
}

// Build constructs the configured chain for one repository.
func Build(entries []config.PolicyEntry) ([]WithMeta, error) {
	var out []WithMeta
	for _, e := range entries {
		var meta struct {
			Shadow bool `yaml:"shadow"`
		}
		if e.Raw != nil {
			if err := e.Raw.Decode(&meta); err != nil {
				return nil, fmt.Errorf("policy %s: %w", e.Name, err)
			}
		}
		var (
			p   Policy
			err error
		)
		switch e.Name {
		case "merge-dependency-updates":
			p, err = NewDepUpdates(e.Raw)
		default:
			err = fmt.Errorf("unknown policy %q", e.Name)
		}
		if err != nil {
			return nil, err
		}
		out = append(out, WithMeta{Policy: p, Shadow: meta.Shadow})
	}
	return out, nil
}
