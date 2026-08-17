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
	calls         []string
	failN         int
	authErr       bool
	failAutoMerge bool
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

func (f *fakeWriter) EnableAutoMerge(_ context.Context, repo string, n int, method string) (string, error) {
	call := fmt.Sprintf("automerge %s#%d --%s", repo, n, method)
	if f.failAutoMerge {
		f.calls = append(f.calls, call)
		return "", errors.New("auto-merge not allowed on this repo")
	}
	return f.record(call)
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

func storedActionError(t *testing.T, st *store.Store, jobID int64) string {
	t.Helper()
	acts, err := st.ActionsForJob(jobID)
	require.NoError(t, err)
	require.Len(t, acts, 1)
	return acts[0].Error
}

func Test_Execute_CancellationDoesNotMaskTheRealFailure(t *testing.T) {
	t.Run("a fault from an earlier attempt survives the cancellation", func(t *testing.T) {
		fw := &fakeWriter{failN: 99}
		a, st, jobID := newActor(t, fw)
		ctx, cancel := context.WithCancel(context.Background())
		a.Sleep = func(time.Duration) { cancel() }

		_, err := a.Execute(ctx, jobID, mergeAction(), false)
		require.ErrorContains(t, err, "transient gh failure")
		require.NotContains(t, err.Error(), "context canceled",
			"the cancellation is incidental; the gh fault is the diagnosis")
		require.Contains(t, storedActionError(t, st, jobID), "transient gh failure")
	})

	t.Run("a cancellation before any attempt is still reported", func(t *testing.T) {
		fw := &fakeWriter{}
		a, st, jobID := newActor(t, fw)
		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		_, err := a.Execute(ctx, jobID, mergeAction(), false)
		require.ErrorContains(t, err, "context canceled")
		require.Empty(t, fw.calls)
		require.Contains(t, storedActionError(t, st, jobID), "context canceled")
	})
}

func approveAndAutoMergeAction() policy.Action {
	return policy.Action{Kind: "approve_and_automerge",
		Params: map[string]string{"repo": "a/b", "number": "1", "method": "squash"}}
}

func Test_Execute_ApproveAndAutoMerge(t *testing.T) {
	t.Run("approves first, then hands the merge to GitHub", func(t *testing.T) {
		fw := &fakeWriter{}
		a, _, jobID := newActor(t, fw)
		out, err := a.Execute(context.Background(), jobID, approveAndAutoMergeAction(), false)
		require.NoError(t, err)
		require.Equal(t, []string{"approve a/b#1", "automerge a/b#1 --squash"}, fw.calls)
		require.Contains(t, out, "approved")
		require.Contains(t, out, "auto-merge enabled")
	})

	t.Run("a failed auto-merge says the review already landed", func(t *testing.T) {
		fw := &fakeWriter{failAutoMerge: true}
		a, _, jobID := newActor(t, fw)
		_, err := a.Execute(context.Background(), jobID, approveAndAutoMergeAction(), false)
		require.ErrorContains(t, err, "enable auto-merge (review already approved)")
		require.ErrorContains(t, err, "auto-merge not allowed on this repo")
	})

	t.Run("a failed approve does not reach the merge", func(t *testing.T) {
		fw := &fakeWriter{authErr: true}
		a, _, jobID := newActor(t, fw)
		_, err := a.Execute(context.Background(), jobID, approveAndAutoMergeAction(), false)
		require.ErrorContains(t, err, "approve:")
		require.Equal(t, []string{"approve a/b#1"}, fw.calls)
	})

	t.Run("shadow records without calling GitHub", func(t *testing.T) {
		fw := &fakeWriter{}
		a, _, jobID := newActor(t, fw)
		out, err := a.Execute(context.Background(), jobID, approveAndAutoMergeAction(), true)
		require.NoError(t, err)
		require.Equal(t, "shadow", out)
		require.Empty(t, fw.calls, "shadow must not approve or enable auto-merge")
	})
}

func Test_RetryBudgetFitsInsideTheClientTimeout(t *testing.T) {
	// The API clients cancel at 30s and hand us that context; if the backoff
	// schedule reached it, the last attempt would die and report the
	// cancellation rather than the fault.
	var total time.Duration
	for attempt := 1; attempt < maxAttempts; attempt++ {
		total += time.Duration(attempt) * retryBackoff
	}
	require.Less(t, total, 15*time.Second,
		"leave room for %d dispatches inside the 30s client timeout", maxAttempts)
}
