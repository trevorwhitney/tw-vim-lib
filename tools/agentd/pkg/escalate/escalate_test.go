package escalate

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// fakeWriter satisfies github.Writer and records every write.
type fakeWriter struct{ merges, approvals, comments []string }

var _ github.Writer = (*fakeWriter)(nil)

func (f *fakeWriter) MergePR(_ context.Context, repo string, n int, method string) (string, error) {
	f.merges = append(f.merges, fmt.Sprintf("%s#%d --%s", repo, n, method))
	return "merged", nil
}

func (f *fakeWriter) ApprovePR(_ context.Context, repo string, n int) (string, error) {
	f.approvals = append(f.approvals, fmt.Sprintf("%s#%d", repo, n))
	return "approved", nil
}

func (f *fakeWriter) CommentPR(_ context.Context, repo string, n int, _ string) (string, error) {
	f.comments = append(f.comments, fmt.Sprintf("%s#%d", repo, n))
	return "commented", nil
}

type fixture struct {
	m       *Manager
	st      *store.Store
	act     *actor.Actor
	gh      *fakeWriter
	banners *[]string
	badge   string
	now     *time.Time
}

func setup(t *testing.T) fixture {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	now := time.Now()
	badge := filepath.Join(t.TempDir(), "badge")
	banners := &[]string{}
	n := notify.New("all", badge)
	n.NotifyFn = func(title, _ string) error {
		*banners = append(*banners, title)
		return nil
	}
	gh := &fakeWriter{}
	a := &actor.Actor{Store: st, GH: gh, Sleep: func(time.Duration) {}}
	m := &Manager{
		Store: st, Notify: n,
		RenotifyAfter: 4 * time.Hour, ParkAfter: 24 * time.Hour,
		Now: func() time.Time { return now },
	}
	return fixture{m: m, st: st, act: a, gh: gh, banners: banners, badge: badge, now: &now}
}

func (f fixture) job(t *testing.T) int64 {
	t.Helper()
	id, err := f.st.CreateJob("pr", "a/b", 1, "sha-"+time.Now().String())
	require.NoError(t, err)
	return id
}

func Test_Create_LosesWhenJobNotActive(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "", "first?", "", nil)) // queued -> waiting_input

	err := f.m.Create(jobID, "", "second?", "", nil)
	require.ErrorIs(t, err, ErrJobNotActive)

	escs, err := f.st.OpenEscalations()
	require.NoError(t, err)
	require.Len(t, escs, 1, "a lost claim must not create an escalation")
}

func Test_Create_ParksJobNotifiesAndBadges(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	act := &policy.Action{Kind: "merge_pr", Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}

	require.NoError(t, f.m.Create(jobID, "", "merge?", "advice", act))

	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)

	badge, err := os.ReadFile(f.badge)
	require.NoError(t, err)
	require.Equal(t, "1", string(badge))
	require.NotEmpty(t, *f.banners, "banner fired (banner=all)")
}

func Test_Create_WithoutActionIsWaitingInput(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "", "what do?", "", nil))
	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_input", job.State)
}

func Test_Resolve_ApproveExecutesAttachedAction(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	act := &policy.Action{Kind: "merge_pr", Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}
	require.NoError(t, f.m.Create(jobID, "", "merge?", "", act))
	esc, ok, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)

	require.NoError(t, f.m.Resolve(context.Background(), esc.ID, "approve", "", "", f.act))

	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)

	require.Equal(t, []string{"a/b#1 --squash"}, f.gh.merges, "approval must execute the attached merge")

	err = f.m.Resolve(context.Background(), esc.ID, "approve", "", "", f.act)
	require.Error(t, err, "resolving twice must fail")
}

func Test_Resolve_RejectRequiresReason(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "", "merge?", "", &policy.Action{Kind: "merge_pr", Params: map[string]string{}}))
	esc, _, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)

	require.Error(t, f.m.Resolve(context.Background(), esc.ID, "reject", "", "", f.act))

	require.NoError(t, f.m.Resolve(context.Background(), esc.ID, "reject", "wrong direction", "", f.act))
	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "rejected", job.State)
}

func Test_Resolve_UnsupportedResolution(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "", "q", "", nil))
	esc, _, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	err = f.m.Resolve(context.Background(), esc.ID, "answer", "", "", f.act)
	require.Error(t, err, "answer without text should fail")
}

func Test_Sweep_RenotifiesAndParks(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "", "q", "", nil))
	count := len(*f.banners)

	*f.now = f.now.Add(5 * time.Hour)
	require.NoError(t, f.m.Sweep())
	require.Greater(t, len(*f.banners), count, "stale escalation re-notifies")
	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_input", job.State)

	*f.now = f.now.Add(25 * time.Hour)
	require.NoError(t, f.m.Sweep())
	job, err = f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "parked", job.State)

	esc, ok, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok, "parked escalation stays open and resolvable")
	_ = esc
}

// fixtureManager is a test helper that returns a Manager with injected
// dependencies (temp store, notifier with no banner output, and Now fixed 48h
// ahead so ParkAfter triggers).
func fixtureManager(t *testing.T) (*Manager, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	now := time.Now().Add(48 * time.Hour)
	m := &Manager{
		Store:         st,
		Notify:        &notify.Notifier{Banner: "none"},
		RenotifyAfter: 4 * time.Hour,
		ParkAfter:     24 * time.Hour,
		Now:           func() time.Time { return now },
	}
	return m, st
}

type fakeFinalizer struct{ calls []string }

func (f *fakeFinalizer) Finalize(_ context.Context, jobID int64, state, outcome, _ string) error {
	f.calls = append(f.calls, fmt.Sprintf("%d:%s/%s", jobID, state, outcome))
	return nil
}

type fakeContinuer struct{ calls []string }

func (f *fakeContinuer) Continue(_ context.Context, jobID int64, answer string) error {
	f.calls = append(f.calls, fmt.Sprintf("%d:%s", jobID, answer))
	return nil
}

func TestApproveWithoutActionAcknowledges(t *testing.T) {
	m, st := fixtureManager(t)
	jobID, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	id, err := st.CreateEscalation(jobID, "waiting_approval", "consult verdict: lgtm", "advice", "", "")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(jobID, "waiting_approval"))

	require.NoError(t, m.Resolve(context.Background(), id, "approve", "", "", nil))

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acknowledged", job.Outcome)
}

func TestAnswerResolutionContinues(t *testing.T) {
	m, st := fixtureManager(t)
	cont := &fakeContinuer{}
	m.Cont = cont
	jobID, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	id, err := st.CreateEscalation(jobID, "waiting_input", "which base?", "", "", "")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(jobID, "waiting_input"))

	require.Error(t, m.Resolve(context.Background(), id, "answer", "", "", nil),
		"answer requires answer text")
	require.NoError(t, m.Resolve(context.Background(), id, "answer", "", "use main", nil))

	require.Equal(t, []string{"1:use main"}, cont.calls)
	esc, err := st.GetEscalation(id)
	require.NoError(t, err)
	require.Equal(t, "answer", esc.Resolution)
	require.Equal(t, "use main", esc.Answer)
}

func TestResolveDelegatesToFinalizer(t *testing.T) {
	m, st := fixtureManager(t)
	fin := &fakeFinalizer{}
	m.Final = fin
	jobID, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	id, err := st.CreateEscalation(jobID, "waiting_approval", "q", "", "", "")
	require.NoError(t, err)

	require.NoError(t, m.Resolve(context.Background(), id, "reject", "not now", "", nil))
	require.Equal(t, []string{"1:rejected/rejected"}, fin.calls)

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.NotEqual(t, "rejected", job.State, "finalizer owns the terminal transition")
}

func TestResolveOnTerminalJobOnlyClosesEscalation(t *testing.T) {
	m, st := fixtureManager(t)
	jobID, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	require.NoError(t, st.FinishJob(jobID, "done", "acted", "merged"))
	id, err := m.AttentionID(jobID, "worktree has uncommitted changes")
	require.NoError(t, err)

	require.NoError(t, m.Resolve(context.Background(), id, "approve", "", "", nil))
	esc, err := st.GetEscalation(id)
	require.NoError(t, err)
	require.Equal(t, "resolved", esc.State)
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State, "terminal job untouched")
}

func TestSweepParksOnlyWaitingJobs(t *testing.T) {
	m, st := fixtureManager(t)
	// waiting job: parked
	wj, err := st.CreateJob("pr", "a/b", 1, "s1")
	require.NoError(t, err)
	_, err = st.CreateEscalation(wj, "waiting_approval", "q", "", "", "")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(wj, "waiting_approval"))
	// interactive job: never parked
	ij, err := st.CreateJob("pr", "a/b", 2, "s2")
	require.NoError(t, err)
	_, err = st.CreateEscalation(ij, "waiting_input", "q", "", "", "")
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(ij, "interactive"))
	// attention item on a finished job: never parked
	dj, err := st.CreateJob("pr", "a/b", 3, "s3")
	require.NoError(t, err)
	require.NoError(t, st.FinishJob(dj, "done", "acted", "m"))
	_, err = m.AttentionID(dj, "leftover worktree")
	require.NoError(t, err)

	require.NoError(t, m.Sweep())

	for id, want := range map[int64]string{wj: "parked", ij: "interactive", dj: "done"} {
		job, err := st.GetJob(id)
		require.NoError(t, err)
		require.Equal(t, want, job.State, "job %d", id)
	}
}
