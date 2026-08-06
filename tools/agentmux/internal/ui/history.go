package ui

import (
	"fmt"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

// renderHistoryRow returns the segments for one terminal job.
func renderHistoryRow(j apitypes.Job, now int64) []Segment {
	segs := []Segment{
		{Text: fmt.Sprintf("%s#%d", j.Repo, j.PRNumber), Role: RoleRepo},
		{Text: "  " + j.State, Role: stateRole(j.State)},
	}
	if j.Outcome != "" {
		segs = append(segs, Segment{Text: "  " + j.Outcome, Role: RoleVerdict})
	}
	segs = append(segs, Segment{Text: "  " + humanAge(now-j.FinishedTS), Role: RoleAge})
	if j.Summary != "" {
		segs = append(segs,
			Segment{Text: "  — ", Role: RoleSep},
			Segment{Text: j.Summary, Role: RoleDefault},
		)
	}
	return segs
}
