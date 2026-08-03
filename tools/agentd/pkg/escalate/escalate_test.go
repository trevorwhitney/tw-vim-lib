package escalate

import (
	"context"
	"errors"
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

func Test_Create_ParksJobNotifiesAndBadges(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	act := &policy.Action{Kind: "merge_pr", Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}

	require.NoError(t, f.m.Create(jobID, "merge?", "advice", act))

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
	require.NoError(t, f.m.Create(jobID, "what do?", "", nil))
	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_input", job.State)
}

func Test_Resolve_ApproveExecutesAttachedAction(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	act := &policy.Action{Kind: "merge_pr", Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}
	require.NoError(t, f.m.Create(jobID, "merge?", "", act))
	esc, ok, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.True(t, ok)

	require.NoError(t, f.m.Resolve(context.Background(), esc.ID, "approve", "", f.act))

	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)

	require.Equal(t, []string{"a/b#1 --squash"}, f.gh.merges, "approval must execute the attached merge")

	err = f.m.Resolve(context.Background(), esc.ID, "approve", "", f.act)
	require.Error(t, err, "resolving twice must fail")
}

func Test_Resolve_RejectRequiresReason(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "merge?", "", &policy.Action{Kind: "merge_pr", Params: map[string]string{}}))
	esc, _, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)

	require.Error(t, f.m.Resolve(context.Background(), esc.ID, "reject", "", f.act))

	require.NoError(t, f.m.Resolve(context.Background(), esc.ID, "reject", "wrong direction", f.act))
	job, err := f.st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "rejected", job.State)
}

func Test_Resolve_UnsupportedResolution(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "q", "", nil))
	esc, _, err := f.st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	err = f.m.Resolve(context.Background(), esc.ID, "answer", "text", f.act)
	require.True(t, errors.Is(err, ErrUnsupportedResolution))
}

func Test_Sweep_RenotifiesAndParks(t *testing.T) {
	f := setup(t)
	jobID := f.job(t)
	require.NoError(t, f.m.Create(jobID, "q", "", nil))
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
