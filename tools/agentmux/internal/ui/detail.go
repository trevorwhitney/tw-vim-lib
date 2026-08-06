package ui

import (
	"fmt"
	"strings"

	"charm.land/lipgloss/v2"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

// detailData is the fully-loaded decision chain for one job.
type detailData struct {
	job        apitypes.Job
	escalation *apitypes.Escalation
	decisions  []apitypes.Decision
	actions    []apitypes.Action
	events     []apitypes.Event
	artifacts  []apitypes.Artifact
}

// renderDetail renders the decision chain as a styled block. It is terminal-
// aware only through styleSegments; layout is plain joined lines.
func renderDetail(d detailData) string {
	var b []string
	headSegs := []Segment{
		{Text: fmt.Sprintf("%s#%d", d.job.Repo, d.job.PRNumber), Role: RoleRepo},
		{Text: "  " + d.job.State, Role: stateRole(d.job.State)},
	}
	if d.job.Outcome != "" {
		headSegs = append(headSegs, Segment{Text: "  " + d.job.Outcome, Role: RoleVerdict})
	}
	b = append(b, styleSegments(headSegs))
	if d.job.HeadSHA != "" {
		b = append(b, styleFooter.Render("head "+d.job.HeadSHA))
	}
	if d.job.Summary != "" {
		b = append(b, d.job.Summary)
	}

	if len(d.decisions) > 0 {
		b = append(b, "", styleTitle.Render("Decisions"))
		for _, dec := range d.decisions {
			line := styleSegments([]Segment{
				{Text: dec.Policy, Role: RoleDefault},
				{Text: "  " + dec.Verdict, Role: RoleVerdict},
			})
			if dec.Rationale != "" {
				line += styleFooter.Render("  — " + dec.Rationale)
			}
			b = append(b, line)
		}
	}

	if len(d.actions) > 0 {
		b = append(b, "", styleTitle.Render("Actions"))
		for _, a := range d.actions {
			label := a.Result
			if a.Simulated {
				label = "simulated (" + a.Result + ")"
			}
			b = append(b, styleSegments([]Segment{
				{Text: a.Kind, Role: RoleDefault},
				{Text: "  " + label, Role: RoleAge},
			}))
		}
	}

	if d.escalation != nil && d.escalation.Advice != "" {
		b = append(b, "", styleTitle.Render("Advice"), d.escalation.Advice)
	}

	if len(d.artifacts) > 0 {
		b = append(b, "", styleTitle.Render("Artifacts"))
		for _, a := range d.artifacts {
			b = append(b, styleFooter.Render("  "+a.Name+"  "+a.Path))
		}
	}

	if len(d.events) > 0 {
		b = append(b, "", styleTitle.Render("Timeline"), styleFooter.Render(summarizeEvents(d.events)))
	}

	b = append(b, "", styleFooter.Render("esc/q close"))
	return lipgloss.JoinVertical(lipgloss.Left, b...)
}

// summarizeEvents renders the lifecycle event types as a compact arrow chain.
func summarizeEvents(events []apitypes.Event) string {
	var types []string
	for _, e := range events {
		types = append(types, e.Type)
	}
	return strings.Join(types, " → ")
}
