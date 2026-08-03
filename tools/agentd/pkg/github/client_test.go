package github

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// fakeExec returns canned output per matched argument substring and counts
// calls per key.
type fakeExec struct {
	responses map[string]string
	errors    map[string]error
	calls     map[string]int
}

func newFakeExec() *fakeExec {
	return &fakeExec{responses: map[string]string{}, errors: map[string]error{}, calls: map[string]int{}}
}

func (f *fakeExec) run(_ context.Context, name string, args ...string) (string, error) {
	joined := name + " " + strings.Join(args, " ")
	for key, err := range f.errors {
		if strings.Contains(joined, key) {
			f.calls[key]++
			return "", err
		}
	}
	for key, out := range f.responses {
		if strings.Contains(joined, key) {
			f.calls[key]++
			return out, nil
		}
	}
	return "", errors.New("unexpected command: " + joined)
}

func Test_ClientImplementsInterface(t *testing.T) {
	var _ Interface = (*Client)(nil)
}

func Test_ListOpenPRs(t *testing.T) {
	fe := newFakeExec()
	fe.responses["pr list --repo grafana/loki"] = `[
		{"number":42,"title":"bump x","isDraft":false,
		 "headRefOid":"abc123","author":{"login":"renovate[bot]"}}]`
	c := New(fe.run)

	prs, err := c.ListOpenPRs("grafana/loki")
	require.NoError(t, err)
	require.Len(t, prs, 1)
	require.Equal(t, PR{Number: 42, Title: "bump x", HeadSHA: "abc123", Author: "renovate[bot]"}, prs[0])
}

func Test_Viewer_Cached(t *testing.T) {
	fe := newFakeExec()
	fe.responses["api user"] = "twhitney\n"
	c := New(fe.run)

	v1, err := c.Viewer()
	require.NoError(t, err)
	v2, err := c.Viewer()
	require.NoError(t, err)
	require.Equal(t, "twhitney", v1)
	require.Equal(t, v1, v2)
	require.Equal(t, 1, fe.calls["api user"], "viewer login is cached")
}

func Test_Writes_ProduceCorrectGhCommands(t *testing.T) {
	ctx := context.Background()
	for name, tc := range map[string]struct {
		call func(c *Client) (string, error)
		want string
	}{
		"merge":   {func(c *Client) (string, error) { return c.MergePR(ctx, "a/b", 1, "squash") }, "pr merge 1 --repo a/b --squash"},
		"approve": {func(c *Client) (string, error) { return c.ApprovePR(ctx, "a/b", 1) }, "pr review 1 --repo a/b --approve"},
		"comment": {func(c *Client) (string, error) { return c.CommentPR(ctx, "a/b", 1, "hi") }, "pr comment 1 --repo a/b --body hi"},
	} {
		t.Run(name, func(t *testing.T) {
			fe := newFakeExec()
			fe.responses[tc.want] = "ok"
			out, err := tc.call(New(fe.run))
			require.NoError(t, err)
			require.Equal(t, "ok", out)
			require.Equal(t, 1, fe.calls[tc.want], "expected gh invocation %q", tc.want)
		})
	}
}

func Test_AuthErrorClassification(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		auth bool
	}{
		"http 401":      {errors.New("gh: HTTP 401: Bad credentials"), true},
		"http 403":      {errors.New("gh: HTTP 403: Forbidden"), true},
		"gh not logged": {errors.New("To get started with GitHub CLI, please run: gh auth login"), true},
		"network":       {errors.New("dial tcp: connection refused"), false},
	} {
		t.Run(name, func(t *testing.T) {
			fe := newFakeExec()
			fe.errors["pr list"] = tc.err
			c := New(fe.run)
			_, err := c.ListOpenPRs("a/b")
			var ae *AuthError
			require.Equal(t, tc.auth, errors.As(err, &ae))
		})
	}
}

func TestDiff(t *testing.T) {
	fe := newFakeExec()
	fe.responses["pr diff 42 --repo a/b"] = "diff --git a/go.mod b/go.mod\n+new line\n"
	c := New(fe.run)

	diff, err := c.Diff("a/b", 42)
	require.NoError(t, err)
	require.Contains(t, diff, "diff --git")
}

func TestPRDetailFields(t *testing.T) {
	fe := newFakeExec()
	fe.responses["pr view 7"] = `{"number":7,"title":"t","body":"the body","url":"https://github.com/a/b/pull/7",
		"isDraft":false,"headRefOid":"s7","baseRefName":"main","author":{"login":"alice"}}`
	c := New(fe.run)

	pr, err := c.GetPR("a/b", 7)
	require.NoError(t, err)
	require.Equal(t, "the body", pr.Body)
	require.Equal(t, "https://github.com/a/b/pull/7", pr.URL)
	require.Equal(t, "main", pr.BaseRef)
}
