package ui

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

func historyModel(t *testing.T, fr *fakeRunner, jobs ...apitypes.Job) Model {
	m := New(Deps{MirrorDir: t.TempDir(), Client: &fakeClient{}, Runner: fr})
	m.activeTab = TabHistory
	m.history = jobs
	return m
}

func Test_HistoryOpenPR(t *testing.T) {
	merged := apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done", Outcome: "acted"}

	t.Run("'o' opens the selected job's PR", func(t *testing.T) {
		fr := &fakeRunner{}
		m := historyModel(t, fr, merged)
		m.Update(pressRune('o'))
		assert.Equal(t, []string{"https://github.com/grafana/loki/pull/44"}, fr.urls)
	})

	t.Run("'o' also works inside the decision-chain detail overlay", func(t *testing.T) {
		fr := &fakeRunner{}
		m := historyModel(t, fr, merged)
		m.showDetail = true
		after, _ := m.Update(pressRune('o'))
		assert.Equal(t, []string{"https://github.com/grafana/loki/pull/44"}, fr.urls)
		assert.True(t, after.(Model).showDetail, "opening a PR must not close the detail")
	})

	t.Run("a job without a PR reports instead of opening", func(t *testing.T) {
		fr := &fakeRunner{}
		m := historyModel(t, fr, apitypes.Job{ID: 9, State: "done"})
		after, _ := m.Update(pressRune('o'))
		assert.Empty(t, fr.urls)
		assert.Contains(t, after.(Model).footer, "no PR")
	})

	t.Run("an empty history is a no-op", func(t *testing.T) {
		fr := &fakeRunner{}
		m := historyModel(t, fr)
		m.Update(pressRune('o'))
		assert.Empty(t, fr.urls)
	})
}

func Test_RenderHistoryRow(t *testing.T) {
	const now = int64(1000)
	t.Run("acted job shows outcome and age", func(t *testing.T) {
		j := apitypes.Job{ID: 3, Repo: "grafana/loki", PRNumber: 44, State: "done",
			Outcome: "acted", Summary: "merged", FinishedTS: 700}
		assert.Equal(t, []Segment{
			{Text: "grafana/loki#44", Role: RoleRepo},
			{Text: "  done", Role: RoleStateTerminalOK},
			{Text: "  acted", Role: RoleVerdict},
			{Text: "  5m", Role: RoleAge},
			{Text: "  — ", Role: RoleSep},
			{Text: "merged", Role: RoleDefault},
		}, renderHistoryRow(j, now))
	})
	t.Run("failed job is red", func(t *testing.T) {
		j := apitypes.Job{ID: 5, Repo: "grafana/loki", PRNumber: 46, State: "failed",
			Outcome: "failed", FinishedTS: 1000}
		got := renderHistoryRow(j, now)
		assert.Equal(t, Segment{Text: "  failed", Role: RoleStateTerminalBad}, got[1])
	})
	t.Run("job without outcome omits the verdict segment", func(t *testing.T) {
		j := apitypes.Job{ID: 6, Repo: "grafana/loki", PRNumber: 47, State: "done", FinishedTS: 940}
		got := renderHistoryRow(j, now)
		for _, s := range got {
			assert.NotEqual(t, RoleVerdict, s.Role)
		}
		assert.Equal(t, Segment{Text: "  1m", Role: RoleAge}, got[2])
	})
}
