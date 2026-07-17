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

// RenderRow returns the plain-text label for a node. Lip Gloss styling is
// applied by the list delegate; this function owns the content/layout so it can
// be tested without a terminal.
func RenderRow(n tree.Node, summary string, now int64) string {
	indent := strings.Repeat("  ", n.Depth)
	switch n.Kind {
	case tree.KindProject:
		return indent + n.Project
	case tree.KindWorktree:
		tag := ""
		if n.IsMain {
			tag = " [main]"
		}
		if n.Validity == "gone" {
			return fmt.Sprintf("%s%s%s  (removed)", indent, n.Worktree, tag)
		}
		attn := ""
		if n.NeedsAttention {
			attn = " ⚠"
		}
		return fmt.Sprintf("%s%s%s  [%dw · %dq · %ds]%s  — %s",
			indent, n.Worktree, tag, n.Working, n.Waiting, n.Saved, attn, summary)
	case tree.KindAgent:
		r := n.Record
		life := store.Liveness(r, now)
		suffix := life
		if life == "saved" {
			suffix = fmt.Sprintf("saved %s ago", humanAge(store.AgeSecs(r, now)))
		}
		attn := ""
		if store.NeedsAttention(r, now) {
			attn = " ⚠"
		}
		return fmt.Sprintf("%s%s#%d  %s · %s%s", indent, r.Mode, r.Idx, r.Status, suffix, attn)
	}
	return ""
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
