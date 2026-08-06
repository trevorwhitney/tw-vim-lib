package ui

import (
	"fmt"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

// stateRole maps a job state to its color role. It lives in fleet.go but is
// shared: history.go and detail.go also call it.
func stateRole(state string) SegmentRole {
	switch state {
	case "running", "preparing", "interactive", "finalizing":
		return RoleStateActive
	case "waiting_input", "waiting_approval", "parked":
		return RoleStateWaiting
	case "done", "skipped":
		return RoleStateTerminalOK
	case "failed", "rejected":
		return RoleStateTerminalBad
	default:
		return RoleDefault
	}
}

// renderFleetRow returns the segments for one non-terminal job.
func renderFleetRow(j apitypes.Job, now int64) []Segment {
	segs := []Segment{
		{Text: fmt.Sprintf("%s#%d", j.Repo, j.PRNumber), Role: RoleRepo},
		{Text: "  " + j.State, Role: stateRole(j.State)},
		{Text: "  " + humanAge(now-j.UpdatedTS), Role: RoleAge},
	}
	detail := j.Summary
	if j.State == "failed" && j.Error != "" {
		detail = j.Error
	}
	if detail != "" {
		segs = append(segs,
			Segment{Text: "  — ", Role: RoleSep},
			Segment{Text: detail, Role: RoleDefault},
		)
	}
	return segs
}

// fleetHeader returns the daemon-health header as segment lines: a poller line
// (paused/live + open-escalation count) and one line per repo with its poller
// state (last poll age, auth error, or last error).
func fleetHeader(st apitypes.Status, now int64) [][]Segment {
	poller := "polling"
	role := RoleStateActive
	if st.Paused {
		poller, role = "PAUSED", RoleStateWaiting
	}
	lines := [][]Segment{{
		{Text: poller, Role: role},
		{Text: fmt.Sprintf("  · %d open", st.OpenEscalations), Role: RoleAge},
	}}
	for _, r := range st.Repos {
		line := []Segment{{Text: "  " + r.Repo, Role: RoleDefault}}
		switch {
		case r.AuthError:
			line = append(line, Segment{Text: "  AUTH ERROR — polling stopped", Role: RoleStateTerminalBad})
		case r.LastError != "":
			line = append(line, Segment{Text: "  " + r.LastError, Role: RoleStateTerminalBad})
		case r.LastPollTS > 0:
			line = append(line, Segment{Text: "  polled " + humanAge(now-r.LastPollTS) + " ago", Role: RoleAge})
		default:
			line = append(line, Segment{Text: "  never polled", Role: RoleAge})
		}
		lines = append(lines, line)
	}
	return lines
}
