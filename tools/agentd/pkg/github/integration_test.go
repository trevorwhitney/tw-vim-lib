//go:build integration

package github

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

// Verifies the gh contract against real GitHub. Read-only and idempotent.
// Requires an authenticated gh CLI.
// Run: go test -tags integration ./pkg/github/ -v
func Test_Integration_ReadOnlyContract(t *testing.T) {
	c := New(execx.Command)

	login, err := c.Viewer()
	require.NoError(t, err)
	require.NotEmpty(t, login)

	const repo = "cli/cli" // public, active, always has open PRs
	prs, err := c.ListOpenPRs(repo)
	require.NoError(t, err)
	require.NotEmpty(t, prs)
	require.NotZero(t, prs[0].Number)
	require.NotEmpty(t, prs[0].HeadSHA)
	require.NotEmpty(t, prs[0].Author)

	pr, err := c.GetPR(repo, prs[0].Number)
	require.NoError(t, err)
	require.Equal(t, prs[0].Number, pr.Number)

	facts, err := c.Facts(repo, pr.Number)
	require.NoError(t, err)
	require.Contains(t, []CIState{CISuccess, CIPending, CIFailure}, facts.CI)
	require.Contains(t, []Mergeability{MergeClean, MergeDirty, MergeUnknown}, facts.Mergeable)

	files, _, err := c.ChangedFiles(repo, pr.Number)
	require.NoError(t, err)
	require.NotEmpty(t, files)
}
