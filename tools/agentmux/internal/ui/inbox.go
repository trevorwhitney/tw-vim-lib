package ui

import (
	"fmt"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

// renderInboxRow returns the segments for one open escalation. The leading
// marker encodes the escalation kind; approval items append their attached
// action so the operator sees what an approve would execute.
func renderInboxRow(it apitypes.InboxItem, now int64) []Segment {
	var segs []Segment
	switch it.Escalation.Kind {
	case "waiting_approval":
		segs = append(segs, Segment{Text: "⚑ ", Role: RoleStateWaiting})
	case "waiting_input":
		segs = append(segs, Segment{Text: "? ", Role: RoleStateWaiting})
	case "attention":
		segs = append(segs, Segment{Text: "⚠ ", Role: RoleAttention})
	default:
		segs = append(segs, Segment{Text: "• ", Role: RoleSep})
	}
	segs = append(segs,
		Segment{Text: fmt.Sprintf("%s#%d", it.Job.Repo, it.Job.PRNumber), Role: RoleRepo},
		Segment{Text: "  " + humanAge(now-it.Escalation.TS), Role: RoleAge},
	)
	if it.Escalation.ActionKind != "" {
		segs = append(segs, Segment{Text: "  " + it.Escalation.ActionKind, Role: RoleVerdict})
	}
	q := it.Escalation.Question
	if q == "" {
		q = it.Job.Summary
	}
	if q != "" {
		segs = append(segs,
			Segment{Text: "  — ", Role: RoleSep},
			Segment{Text: q, Role: RoleDefault},
		)
	}
	return segs
}
