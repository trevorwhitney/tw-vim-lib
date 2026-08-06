package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func Test_RenderFleetRow(t *testing.T) {
	const now = int64(1000)
	t.Run("running consult is active-green with repo and age", func(t *testing.T) {
		j := apitypes.Job{ID: 2, Repo: "grafana/loki", PRNumber: 43, State: "running",
			Summary: "analyzing", UpdatedTS: 940}
		assert.Equal(t, []Segment{
			{Text: "grafana/loki#43", Role: RoleRepo},
			{Text: "  running", Role: RoleStateActive},
			{Text: "  1m", Role: RoleAge},
			{Text: "  — ", Role: RoleSep},
			{Text: "analyzing", Role: RoleDefault},
		}, renderFleetRow(j, now))
	})
	t.Run("waiting state is yellow", func(t *testing.T) {
		j := apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "waiting_approval",
			Summary: "awaiting approval", UpdatedTS: 1000}
		assert.Equal(t, []Segment{
			{Text: "grafana/loki#44", Role: RoleRepo},
			{Text: "  waiting_approval", Role: RoleStateWaiting},
			{Text: "  0s", Role: RoleAge},
			{Text: "  — ", Role: RoleSep},
			{Text: "awaiting approval", Role: RoleDefault},
		}, renderFleetRow(j, now))
	})
	t.Run("failed state is red and shows the error as detail", func(t *testing.T) {
		j := apitypes.Job{ID: 4, Repo: "grafana/loki", PRNumber: 45, State: "failed",
			Error: "gh timeout", UpdatedTS: 1000}
		assert.Equal(t, []Segment{
			{Text: "grafana/loki#45", Role: RoleRepo},
			{Text: "  failed", Role: RoleStateTerminalBad},
			{Text: "  0s", Role: RoleAge},
			{Text: "  — ", Role: RoleSep},
			{Text: "gh timeout", Role: RoleDefault},
		}, renderFleetRow(j, now))
	})
	t.Run("failed with empty error falls back to summary", func(t *testing.T) {
		j := apitypes.Job{ID: 5, Repo: "grafana/loki", PRNumber: 46, State: "failed",
			Summary: "gave up", UpdatedTS: 1000}
		got := renderFleetRow(j, now)
		assert.Equal(t, Segment{Text: "gave up", Role: RoleDefault}, got[len(got)-1])
	})
}

func Test_FleetHeader(t *testing.T) {
	st := apitypes.Status{
		Paused: true, OpenEscalations: 1,
		Repos: []apitypes.RepoStatus{
			{Repo: "grafana/loki", LastPollTS: 900},
			{Repo: "grafana/mimir", AuthError: true},
			{Repo: "grafana/tempo", LastError: "rate limited"},
			{Repo: "grafana/pyroscope"},
		},
	}
	lines := fleetHeader(st, 1000)
	joined := ""
	for _, l := range lines {
		for _, s := range l {
			joined += s.Text
		}
	}
	assert.Contains(t, joined, "PAUSED")
	assert.Contains(t, joined, "grafana/loki")
	assert.Contains(t, joined, "AUTH ERROR")
	assert.Contains(t, joined, "rate limited")
	assert.Contains(t, joined, "never polled")
}

func Test_stateRole(t *testing.T) {
	for state, want := range map[string]SegmentRole{
		"running": RoleStateActive, "preparing": RoleStateActive,
		"interactive": RoleStateActive, "finalizing": RoleStateActive,
		"waiting_input": RoleStateWaiting, "waiting_approval": RoleStateWaiting,
		"parked": RoleStateWaiting,
		"done":   RoleStateTerminalOK, "skipped": RoleStateTerminalOK,
		"failed": RoleStateTerminalBad, "rejected": RoleStateTerminalBad,
		"": RoleDefault, "bogus": RoleDefault,
	} {
		assert.Equalf(t, want, stateRole(state), "state %q", state)
	}
}
