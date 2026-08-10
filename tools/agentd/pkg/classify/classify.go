// Package classify implements the one-shot classifier contract: a prompt-only
// pure opencode run whose output must be a JSON object with a label from the
// caller's declared set. Any failure means the classifier is unavailable;
// callers must escalate, never act, on error.
package classify

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
)

type Result struct {
	Label      string  `json:"label"`
	Confidence float64 `json:"confidence"`
	Reasoning  string  `json:"reasoning"`
}

// Func is the hook policies consume; nil means no classifier is configured.
type Func func(ctx context.Context, prompt string, labels []string) (Result, error)

type Runner struct {
	OC opencode.Runner
}

func (r *Runner) Classify(ctx context.Context, prompt string, labels []string) (Result, error) {
	labelJSON, err := json.Marshal(labels)
	if err != nil {
		return Result{}, err
	}
	full := fmt.Sprintf(
		"%s\n\nRespond with ONLY a JSON object, no prose: "+
			`{"label": <one of %s>, "confidence": <number 0..1>, "reasoning": <short string>}`,
		prompt, labelJSON)
	out, err := r.OC.Run(ctx, opencode.Request{Pure: true, Prompt: full})
	if err != nil {
		return Result{}, fmt.Errorf("classifier invocation: %w", err)
	}
	return Parse(out, labels)
}

// Parse extracts and validates the classifier's JSON object from raw model
// output that may include surrounding prose.
func Parse(out string, labels []string) (Result, error) {
	start := strings.Index(out, "{")
	end := strings.LastIndex(out, "}")
	if start < 0 || end <= start {
		return Result{}, fmt.Errorf("no JSON object in classifier output")
	}
	var aux struct {
		Label      string   `json:"label"`
		Confidence *float64 `json:"confidence"`
		Reasoning  string   `json:"reasoning"`
	}
	if err := json.Unmarshal([]byte(out[start:end+1]), &aux); err != nil {
		return Result{}, fmt.Errorf("classifier output is not valid JSON: %w", err)
	}
	if !slices.Contains(labels, aux.Label) {
		return Result{}, fmt.Errorf("classifier label %q not in declared set %v", aux.Label, labels)
	}
	if aux.Confidence == nil {
		return Result{}, fmt.Errorf("classifier output missing confidence")
	}
	if *aux.Confidence < 0 || *aux.Confidence > 1 {
		return Result{}, fmt.Errorf("classifier confidence %v out of range", *aux.Confidence)
	}
	return Result{Label: aux.Label, Confidence: *aux.Confidence, Reasoning: aux.Reasoning}, nil
}
