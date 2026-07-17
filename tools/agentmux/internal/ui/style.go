package ui

import (
	"strings"

	"charm.land/lipgloss/v2"
)

// Foreground-only styles keyed by ANSI slot (0-15) plus attributes. No
// background is ever set, so output adapts to the terminal's active theme.
var (
	styleProject   = lipgloss.NewStyle().Foreground(lipgloss.Color("4")).Bold(true)
	styleMain      = lipgloss.NewStyle().Foreground(lipgloss.Color("5"))
	styleWorking   = lipgloss.NewStyle().Foreground(lipgloss.Color("2"))
	styleWaiting   = lipgloss.NewStyle().Foreground(lipgloss.Color("3"))
	styleSaved     = lipgloss.NewStyle().Foreground(lipgloss.Color("1"))
	styleAttention = lipgloss.NewStyle().Foreground(lipgloss.Color("1")).Bold(true)
	styleFaint     = lipgloss.NewStyle().Faint(true)
	styleRemoved   = lipgloss.NewStyle().Faint(true).Italic(true)
	stylePlain     = lipgloss.NewStyle()
)

var roleStyles = map[SegmentRole]lipgloss.Style{
	RoleProject:      styleProject,
	RoleWorktree:     stylePlain,
	RoleMain:         styleMain,
	RoleCountWorking: styleWorking,
	RoleCountWaiting: styleWaiting,
	RoleCountSaved:   styleSaved,
	RoleCountZero:    styleFaint,
	RoleAgentWorking: styleWorking,
	RoleAgentWaiting: styleWaiting,
	RoleAttention:    styleAttention,
	RoleAge:          styleFaint,
	RoleRemoved:      styleRemoved,
	RoleSep:          styleFaint,
	RoleDefault:      stylePlain,
}

// styleSegments renders each segment's text with the style for its role and
// concatenates the result. A plain style emits text verbatim.
func styleSegments(segs []Segment) string {
	var b strings.Builder
	for _, s := range segs {
		st, ok := roleStyles[s.Role]
		if !ok {
			st = stylePlain
		}
		b.WriteString(st.Render(s.Text))
	}
	return b.String()
}
