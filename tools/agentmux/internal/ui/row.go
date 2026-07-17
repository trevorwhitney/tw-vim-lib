package ui

import (
	"fmt"
	"strings"

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
		return nil
	case tree.KindAgent:
		return nil
	}
	return nil
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
