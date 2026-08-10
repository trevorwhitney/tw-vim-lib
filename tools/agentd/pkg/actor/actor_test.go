package actor

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// fakeWriter records write calls; failN fails that many transiently, authErr
// fails every call with a github.AuthError.
type fakeWriter struct {
	calls   []string
	failN   int
	authErr bool
}

var _ github.Writer = (*fakeWriter)(nil)

func (f *fakeWriter) record(call string) (string, error) {
	f.calls = append(f.calls, call)
	if f.authErr {
		return "", &github.AuthError{Msg: "HTTP 401"}
	}
	if f.failN > 0 {
		f.failN--
		return "", errors.New("transient gh failure")
	}
	return "ok", nil
}

func (f *fakeWriter) MergePR(_ context.Context, repo string, n int, method string) (string, error) {
	return f.record(fmt.Sprintf("merge %s#%d --%s", repo, n, method))
}
func (f *fakeWriter) ApprovePR(_ context.Context, repo string, n int) (string, error) {
	return f.record(fmt.Sprintf("approve %s#%d", repo, n))
}
func (f *fakeWriter) CommentPR(_ context.Context, repo string, n int, body string) (string, error) {
	return f.record(fmt.Sprintf("comment %s#%d: %s", repo, n, body))
}

func newActor(t *testing.T, fw *fakeWriter) (*Actor, *store.Store, int64) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	jobID, err := st.CreateJob("pr", "a/b", 1, "sha1")
	require.NoError(t, err)
	return &Actor{Store: st, GH: fw, Sleep: func(time.Duration) {}}, st, jobID
}

func mergeAction() policy.Action {
	return policy.Action{Kind: "merge_pr",
		Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}
}

func Test_Execute_DispatchesToWriter(t *testing.T) {
	for name, tc := range map[string]struct {
		action policy.Action
		want   string
	}{
		"merge": {mergeAction(), "merge a/b#1 --squash"},
		"approve": {policy.Action{Kind: "approve_pr",
			Params: map[string]string{"repo": "a/b", "number": "1"}}, "approve a/b#1"},
		"comment": {policy.Action{Kind: "comment_pr",
			Params: map[string]string{"repo": "a/b", "number": "1", "body": "hi"}}, "comment a/b#1: hi"},
	} {
		t.Run(name, func(t *testing.T) {
			fw := &fakeWriter{}
			a, _, jobID := newActor(t, fw)
			out, err := a.Execute(context.Background(), jobID, tc.action, false)
			require.NoError(t, err)
			require.Equal(t, "ok", out)
			require.Equal(t, []string{tc.want}, fw.calls)
		})
	}
}

func Test_Execute_IsIdempotent(t *testing.T) {
	fw := &fakeWriter{}
	a, _, jobID := newActor(t, fw)

	_, err := a.Execute(context.Background(), jobID, mergeAction(), false)
	require.NoError(t, err)
	_, err = a.Execute(context.Background(), jobID, mergeAction(), false)
	require.NoError(t, err)
	require.Len(t, fw.calls, 1, "second execution must be a no-op")
}

func Test_Execute_ShadowAndDryRunDoNotExecute(t *testing.T) {
	fw := &fakeWriter{}
	a, _, jobID := newActor(t, fw)
	out, err := a.Execute(context.Background(), jobID, mergeAction(), true)
	require.NoError(t, err)
	require.Equal(t, "shadow", out)
	require.Empty(t, fw.calls)

	fw2 := &fakeWriter{}
	a2, _, jobID2 := newActor(t, fw2)
	a2.DryRun = true
	out, err = a2.Execute(context.Background(), jobID2, mergeAction(), false)
	require.NoError(t, err)
	require.Equal(t, "dry-run", out)
	require.Empty(t, fw2.calls)
}

func Test_Execute_RetriesThenSucceeds(t *testing.T) {
	fw := &fakeWriter{failN: 2}
	a, _, jobID := newActor(t, fw)
	out, err := a.Execute(context.Background(), jobID, mergeAction(), false)
	require.NoError(t, err)
	require.Equal(t, "ok", out)
	require.Len(t, fw.calls, 3)
}

func Test_Execute_ExhaustsRetries(t *testing.T) {
	fw := &fakeWriter{failN: 99}
	a, _, jobID := newActor(t, fw)
	_, err := a.Execute(context.Background(), jobID, mergeAction(), false)
	require.Error(t, err)
	require.Len(t, fw.calls, 3)

	fw.failN = 0
	out, err := a.Execute(context.Background(), jobID, mergeAction(), false)
	require.NoError(t, err)
	require.Equal(t, "ok", out, "failed action must be retryable")
}

func Test_Execute_UnknownKind(t *testing.T) {
	fw := &fakeWriter{}
	a, _, jobID := newActor(t, fw)
	_, err := a.Execute(context.Background(), jobID, policy.Action{Kind: "rm_rf"}, false)
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "unknown action kind"))
	require.Empty(t, fw.calls)
}

func Test_Execute_AuthErrorNotRetried(t *testing.T) {
	fw := &fakeWriter{authErr: true}
	a, _, jobID := newActor(t, fw)
	_, err := a.Execute(context.Background(), jobID, mergeAction(), false)
	require.Error(t, err)
	var ae *github.AuthError
	require.ErrorAs(t, err, &ae)
	require.Len(t, fw.calls, 1, "auth errors must not be retried")
}

func Test_Execute_CancelledContextStopsRetries(t *testing.T) {
	fw := &fakeWriter{failN: 99}
	a, _, jobID := newActor(t, fw)
	ctx, cancel := context.WithCancel(context.Background())
	a.Sleep = func(time.Duration) { cancel() }
	_, err := a.Execute(ctx, jobID, mergeAction(), false)
	require.Error(t, err)
	require.Len(t, fw.calls, 1, "no further attempts after ctx cancellation")
}
