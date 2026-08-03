package classify

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
)

type ocFake struct {
	reqs []opencode.Request
	out  string
	err  error
}

func (f *ocFake) Run(_ context.Context, req opencode.Request) (string, error) {
	f.reqs = append(f.reqs, req)
	return f.out, f.err
}
func (f *ocFake) Export(context.Context, string) (string, error) { return "", nil }

func TestParseValid(t *testing.T) {
	out := "Some preamble\n{\"label\": \"nit\", \"confidence\": 0.9, \"reasoning\": \"trivial\"}\n"
	res, err := Parse(out, []string{"nit", "substantive"})
	require.NoError(t, err)
	require.Equal(t, "nit", res.Label)
	require.InDelta(t, 0.9, res.Confidence, 0.001)
}

func TestParseRejectsInvalid(t *testing.T) {
	for name, out := range map[string]string{
		"no json":         "I think this is a nit.",
		"unknown label":   `{"label": "banana", "confidence": 0.5, "reasoning": "x"}`,
		"bad confidence":  `{"label": "nit", "confidence": 1.5, "reasoning": "x"}`,
		"missing label":   `{"confidence": 0.5, "reasoning": "x"}`,
		"not json object": `["nit"]`,
	} {
		t.Run(name, func(t *testing.T) {
			_, err := Parse(out, []string{"nit", "substantive"})
			require.Error(t, err)
		})
	}
}

func TestClassifyIsPurePromptOnly(t *testing.T) {
	oc := &ocFake{out: `{"label": "nit", "confidence": 0.7, "reasoning": "small"}`}
	r := &Runner{OC: oc}
	res, err := r.Classify(context.Background(), "is this a nit?", []string{"nit", "substantive"})
	require.NoError(t, err)
	require.Equal(t, "nit", res.Label)
	require.Len(t, oc.reqs, 1)
	require.True(t, oc.reqs[0].Pure, "classifier runs pure")
	require.Empty(t, oc.reqs[0].Agent)
	require.Contains(t, oc.reqs[0].Prompt, "is this a nit?")
	require.Contains(t, oc.reqs[0].Prompt, `"nit"`)
}

func TestClassifierErrorIsUnavailable(t *testing.T) {
	oc := &ocFake{err: errors.New("model exploded")}
	r := &Runner{OC: oc}
	_, err := r.Classify(context.Background(), "q", []string{"a"})
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "model exploded"))
}
