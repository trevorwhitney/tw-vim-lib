// Package checks holds the universal pre-policy checks: conditions under
// which no policy should evaluate a PR at all.
package checks

import "github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"

// Facts is everything the universal checks need about one PR. github.Facts is
// embedded, promoting CI and Mergeable.
type Facts struct {
	PR     github.PR
	Viewer string
	github.Facts
}

// Eligible reports whether every universal check passes; when false, reason
// names the failed check.
func Eligible(f Facts) (bool, string) {
	switch {
	case f.PR.Draft:
		return false, "draft"
	case f.PR.Author == f.Viewer:
		return false, "authored by operator"
	case f.Mergeable == github.MergeDirty:
		return false, "conflicts with base branch"
	case f.Mergeable == github.MergeUnknown:
		return false, "mergeability not yet computed"
	case f.CI == github.CIFailure:
		return false, "ci failing"
	case f.CI == github.CIPending:
		return false, "ci pending"
	}
	return true, ""
}
