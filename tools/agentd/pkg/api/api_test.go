package api

import (
	"context"
	"log/slog"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// The api tests exercise the full server over a real unix socket using the
// same fakes as the engine tests.

type fakeGH struct {
	pr    github.PR
	files []string
}

var _ github.Reader = (*fakeGH)(nil)

func (f *fakeGH) ListOpenPRs(string) ([]github.PR, error)          { return []github.PR{f.pr}, nil }
func (f *fakeGH) GetPR(string, int) (github.PR, error)             { return f.pr, nil }
func (f *fakeGH) ChangedFiles(string, int) ([]string, bool, error) { return f.files, false, nil }
func (f *fakeGH) Facts(string, int) (github.Facts, error) {
	return github.Facts{CI: github.CISuccess, Mergeable: github.MergeClean}, nil
}
func (f *fakeGH) Viewer() (string, error) { return "twhitney", nil }

type okWriter struct{}

var _ github.Writer = okWriter{}

func (okWriter) MergePR(context.Context, string, int, string) (string, error)   { return "merged", nil }
func (okWriter) ApprovePR(context.Context, string, int) (string, error)         { return "approved", nil }
func (okWriter) CommentPR(context.Context, string, int, string) (string, error) { return "commented", nil }

func setup(t *testing.T, files []string) (*Client, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	act := &actor.Actor{Store: st, GH: okWriter{}, Sleep: func(time.Duration) {}}
	n := &notify.Notifier{Banner: "none"}
	esc := &escalate.Manager{Store: st, Notify: n, RenotifyAfter: time.Hour, ParkAfter: 24 * time.Hour, Now: time.Now}
	dep, err := policy.NewDepUpdates(nil)
	require.NoError(t, err)

	eng := &engine.Engine{
		Store: st,
		GH:    &fakeGH{pr: github.PR{Number: 42, HeadSHA: "abc", Author: "renovate[bot]"}, files: files},
		Actor: act, Esc: esc,
		Chains: map[string][]policy.WithMeta{"grafana/loki": {{Policy: dep}}},
		Log:    slog.Default(),
	}

	sock := filepath.Join(t.TempDir(), "agentd.sock")
	srv := &Server{Engine: eng, Esc: esc, Actor: act, Store: st}
	ln, err := Listen(sock)
	require.NoError(t, err)
	httpSrv := &http.Server{Handler: srv.Handler()}
	go func() { _ = httpSrv.Serve(ln) }()
	t.Cleanup(func() { _ = httpSrv.Close() })

	return NewClient(sock), st
}

func Test_StatusEndpoint(t *testing.T) {
	c, _ := setup(t, []string{"go.mod"})
	st, err := c.Status()
	require.NoError(t, err)
	require.False(t, st.Paused)
	require.Zero(t, st.OpenEscalations)
	require.Len(t, st.Repos, 1)
}

func Test_EnqueueAndGetJob(t *testing.T) {
	c, _ := setup(t, []string{"go.mod"})
	job, err := c.Enqueue("grafana/loki", 42)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)

	got, err := c.Job(job.ID)
	require.NoError(t, err)
	require.Equal(t, job.ID, got.Job.ID)
	require.Nil(t, got.Escalation)
}

func Test_ResolveFlow(t *testing.T) {
	c, st := setup(t, []string{"go.mod", "main.go"})
	job, err := c.Enqueue("grafana/loki", 42)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)

	got, err := c.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, got.Escalation)

	require.NoError(t, c.Resolve(got.Escalation.ID, "approve", ""))

	final, err := st.GetJob(job.ID)
	require.NoError(t, err)
	require.Equal(t, "done", final.State)

	err = c.Resolve(got.Escalation.ID, "approve", "")
	require.Error(t, err, "second resolve conflicts")
}

func Test_ResolveRejectValidation(t *testing.T) {
	c, _ := setup(t, []string{"go.mod", "main.go"})
	job, err := c.Enqueue("grafana/loki", 42)
	require.NoError(t, err)
	got, err := c.Job(job.ID)
	require.NoError(t, err)

	require.Error(t, c.Resolve(got.Escalation.ID, "reject", ""), "reject without reason is a 400")
	require.NoError(t, c.Resolve(got.Escalation.ID, "reject", "no thanks"))
}

func Test_PollingControl(t *testing.T) {
	c, _ := setup(t, []string{"go.mod"})
	require.NoError(t, c.SetPolling(true))
	st, err := c.Status()
	require.NoError(t, err)
	require.True(t, st.Paused)
}
