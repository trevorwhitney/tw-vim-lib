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

var (
	styleTitle  = lipgloss.NewStyle().Bold(true)
	styleFooter = lipgloss.NewStyle().Faint(true)
	styleStatus = lipgloss.NewStyle().Foreground(lipgloss.Color("1"))
	styleFilter = lipgloss.NewStyle().Faint(true)
)

// Mission-control role styles. Same foreground-only, theme-adaptive rules as
// the block above: never a background, never truecolor.
var (
	styleStateActive  = lipgloss.NewStyle().Foreground(lipgloss.Color("2"))
	styleStateWaiting = lipgloss.NewStyle().Foreground(lipgloss.Color("3"))
	styleTerminalOK   = lipgloss.NewStyle().Faint(true)
	styleTerminalBad  = lipgloss.NewStyle().Foreground(lipgloss.Color("1"))
	styleVerdict      = lipgloss.NewStyle().Foreground(lipgloss.Color("5"))
	styleRepo         = lipgloss.NewStyle().Bold(true)
	styleTabActive    = lipgloss.NewStyle().Bold(true)
	styleTabInactive  = lipgloss.NewStyle().Faint(true)
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

	RoleStateActive:      styleStateActive,
	RoleStateWaiting:     styleStateWaiting,
	RoleStateTerminalOK:  styleTerminalOK,
	RoleStateTerminalBad: styleTerminalBad,
	RoleVerdict:          styleVerdict,
	RoleRepo:             styleRepo,
	RoleTabActive:        styleTabActive,
	RoleTabInactive:      styleTabInactive,
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
