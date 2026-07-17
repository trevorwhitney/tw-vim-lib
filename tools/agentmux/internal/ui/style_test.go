package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_styleSegments_rolesEmitExpectedSGR(t *testing.T) {
	cases := []struct {
		name string
		role SegmentRole
		want string
	}{
		{"project blue bold", RoleProject, "\x1b[1;34m"},
		{"main magenta", RoleMain, "\x1b[35m"},
		{"count working green", RoleCountWorking, "\x1b[32m"},
		{"count waiting yellow", RoleCountWaiting, "\x1b[33m"},
		{"count saved red", RoleCountSaved, "\x1b[31m"},
		{"count zero faint", RoleCountZero, "\x1b[2m"},
		{"agent working green", RoleAgentWorking, "\x1b[32m"},
		{"agent waiting yellow", RoleAgentWaiting, "\x1b[33m"},
		{"attention red bold", RoleAttention, "\x1b[1;31m"},
		{"age faint", RoleAge, "\x1b[2m"},
		{"removed faint italic", RoleRemoved, "\x1b[3;2m"},
		{"sep faint", RoleSep, "\x1b[2m"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := styleSegments([]Segment{{Text: "X", Role: c.role}})
			assert.Contains(t, out, c.want)
		})
	}
}

func Test_styleSegments_defaultAndWorktreeUnstyled(t *testing.T) {
	for _, role := range []SegmentRole{RoleDefault, RoleWorktree} {
		out := styleSegments([]Segment{{Text: "X", Role: role}})
		assert.Equal(t, "X", out)
	}
}

func Test_styleSegments_neverEmitsBackground(t *testing.T) {
	roles := []SegmentRole{
		RoleProject, RoleWorktree, RoleMain, RoleCountWorking, RoleCountWaiting,
		RoleCountSaved, RoleCountZero, RoleAgentWorking, RoleAgentWaiting,
		RoleAttention, RoleAge, RoleRemoved, RoleSep, RoleDefault,
	}
	for _, r := range roles {
		out := styleSegments([]Segment{{Text: "X", Role: r}})
		assert.NotContains(t, out, "48;", "role %d emitted a background SGR", r)
	}
}

func Test_styleSegments_neverEmitsTruecolor(t *testing.T) {
	roles := []SegmentRole{
		RoleProject, RoleMain, RoleCountWorking, RoleCountWaiting,
		RoleCountSaved, RoleAgentWorking, RoleAgentWaiting, RoleAttention,
	}
	for _, r := range roles {
		out := styleSegments([]Segment{{Text: "X", Role: r}})
		assert.NotContains(t, out, "38;2;", "role %d emitted truecolor fg", r)
	}
}

func Test_styleSegments_concatenatesInOrder(t *testing.T) {
	out := styleSegments([]Segment{
		{Text: "a", Role: RoleDefault},
		{Text: "b", Role: RoleDefault},
	})
	assert.Equal(t, "ab", out)
}

func Test_styleSegments_nilIsEmpty(t *testing.T) {
	assert.Equal(t, "", styleSegments(nil))
}
