package ui

import (
	"fmt"
	"strings"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/tree"
)

// SegmentRole classifies a run of row text so the style layer can style it
// without needing the node. Every styling decision is encoded in the role.
type SegmentRole int

const (
	RoleDefault SegmentRole = iota
	RoleProject
	RoleWorktree
	RoleMain
	RoleCountWorking
	RoleCountWaiting
	RoleCountSaved
	RoleCountZero
	RoleAgentWorking
	RoleAgentWaiting
	RoleAttention
	RoleAge
	RoleRemoved
	RoleSep
)

// Segment is a run of text plus the role that determines its style.
type Segment struct {
	Text string
	Role SegmentRole
}

// RenderRow returns the ordered segments for a node. It owns content and
// layout (text, indent, markers, separators, ordering) and is terminal-free so
// it can be unit-tested without rendering. Styling is applied by styleSegments.
func RenderRow(n tree.Node, summary string, now int64) []Segment {
	indent := strings.Repeat("  ", n.Depth)
	switch n.Kind {
	case tree.KindProject:
		return []Segment{{Text: indent + "▸ " + n.Project, Role: RoleProject}}
	case tree.KindWorktree:
		if n.Validity == "gone" {
			return []Segment{
				{Text: indent + n.Worktree, Role: RoleWorktree},
				{Text: "  (removed)", Role: RoleRemoved},
			}
		}
		segs := []Segment{{Text: indent + n.Worktree, Role: RoleWorktree}}
		if n.IsMain {
			segs = append(segs, Segment{Text: " [main]", Role: RoleMain})
		}
		segs = append(segs,
			Segment{Text: "  [", Role: RoleSep},
			countSegment(n.Working, "w", RoleCountWorking),
			Segment{Text: " · ", Role: RoleSep},
			countSegment(n.Waiting, "q", RoleCountWaiting),
			Segment{Text: " · ", Role: RoleSep},
			countSegment(n.Saved, "s", RoleCountSaved),
			Segment{Text: "]", Role: RoleSep},
		)
		if n.NeedsAttention {
			segs = append(segs, Segment{Text: " ⚠", Role: RoleAttention})
		}
		segs = append(segs,
			Segment{Text: "  — ", Role: RoleSep},
			Segment{Text: summary, Role: RoleDefault},
		)
		return segs
	case tree.KindAgent:
		r := n.Record
		lineRole := agentLineRole(r, now)
		segs := []Segment{
			{Text: fmt.Sprintf("%s%s#%d", indent, r.Mode, r.Idx), Role: lineRole},
			{Text: "  " + r.Status, Role: lineRole},
		}
		if store.Liveness(r, now) == "saved" {
			segs = append(segs, Segment{
				Text: fmt.Sprintf(" · saved %s ago", humanAge(store.AgeSecs(r, now))),
				Role: RoleAge,
			})
		} else {
			segs = append(segs, Segment{Text: " · live", Role: RoleAge})
		}
		if store.NeedsAttention(r, now) {
			segs = append(segs, Segment{Text: " ⚠", Role: RoleAttention})
		}
		return segs
	}
	return nil
}

// agentLineRole picks the color role for the agent's name+status line. A stale
// agent is an attention state and takes the waiting (yellow) tone even if its
// status still literally reads "working".
func agentLineRole(r store.Record, now int64) SegmentRole {
	if store.NeedsAttention(r, now) && store.Liveness(r, now) == "saved" {
		return RoleAgentWaiting
	}
	switch r.Status {
	case "working":
		return RoleAgentWorking
	case "waiting":
		return RoleAgentWaiting
	default:
		return RoleDefault
	}
}

// countSegment formats a "<n><suffix>" count, using RoleCountZero when n==0 so
// the style layer dims it, otherwise the given semantic role.
func countSegment(n int, suffix string, role SegmentRole) Segment {
	if n == 0 {
		role = RoleCountZero
	}
	return Segment{Text: fmt.Sprintf("%d%s", n, suffix), Role: role}
}

// humanAge formats a duration in seconds as a compact relative string.
func humanAge(secs int64) string {
	switch {
	case secs < 60:
		return fmt.Sprintf("%ds", secs)
	case secs < 3600:
		return fmt.Sprintf("%dm", secs/60)
	case secs < 86400:
		return fmt.Sprintf("%dh", secs/3600)
	default:
		return fmt.Sprintf("%dd", secs/86400)
	}
}
