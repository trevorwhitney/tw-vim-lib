package ui

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func Test_RenderDetail(t *testing.T) {
	d := detailData{
		job: apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done",
			Outcome: "acted", Summary: "merged", HeadSHA: "abcdef0"},
		decisions: []apitypes.Decision{
			{Policy: "merge-dependency-updates", Verdict: "act", Rationale: "paths allowed"},
		},
		actions: []apitypes.Action{
			{Kind: "merge_pr", Result: "merged", Simulated: false},
			{Kind: "comment_pr", Result: "shadow", Simulated: true},
		},
		artifacts: []apitypes.Artifact{
			{Name: "diff.patch", Path: "/tmp/diff.patch"},
		},
		events: []apitypes.Event{
			{Type: "preparing"}, {Type: "running"},
		},
	}
	out := renderDetail(d)
	assert.Contains(t, out, "grafana/loki#44")
	assert.Contains(t, out, "abcdef0")
	assert.Contains(t, out, "merge-dependency-updates")
	assert.Contains(t, out, "act")
	assert.Contains(t, out, "merge_pr")
	assert.Contains(t, out, "merged")
	// Simulated actions are labelled so shadow/dry-run reads are unambiguous.
	assert.Contains(t, out, "comment_pr")
	assert.True(t, strings.Contains(out, "simulated") || strings.Contains(out, "shadow"))
	assert.Contains(t, out, "diff.patch")
	// Timeline renders the loaded events.
	assert.Contains(t, out, "preparing → running")
}

func Test_RenderDetail_EmptySections(t *testing.T) {
	out := renderDetail(detailData{
		job: apitypes.Job{Repo: "grafana/loki", PRNumber: 44, State: "done"},
	})
	assert.NotContains(t, out, "Decisions")
	assert.NotContains(t, out, "Actions")
	assert.NotContains(t, out, "Artifacts")
	assert.NotContains(t, out, "Timeline")
	assert.NotContains(t, out, "Advice")
	assert.Contains(t, out, "grafana/loki#44")
	assert.Contains(t, out, "esc/q close")
}

func Test_RenderDetail_Advice(t *testing.T) {
	out := renderDetail(detailData{
		job:        apitypes.Job{Repo: "grafana/loki", PRNumber: 44, State: "waiting_approval"},
		escalation: &apitypes.Escalation{Advice: "wait for CI"},
	})
	assert.Contains(t, out, "Advice")
	assert.Contains(t, out, "wait for CI")
}
