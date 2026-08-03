package checks

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
)

func eligibleFacts() Facts {
	return Facts{
		PR:     github.PR{Number: 1, Author: "renovate[bot]", HeadSHA: "s"},
		Viewer: "twhitney",
		Facts:  github.Facts{CI: github.CISuccess, Mergeable: github.MergeClean},
	}
}

func Test_Eligible(t *testing.T) {
	f := eligibleFacts()
	ok, reason := Eligible(f)
	require.True(t, ok)
	require.Empty(t, reason)

	for name, mutate := range map[string]func(*Facts){
		"draft":             func(f *Facts) { f.PR.Draft = true },
		"operator authored": func(f *Facts) { f.PR.Author = "twhitney" },
		"conflicts":         func(f *Facts) { f.Mergeable = github.MergeDirty },
		"mergeable unknown": func(f *Facts) { f.Mergeable = github.MergeUnknown },
		"ci failing":        func(f *Facts) { f.CI = github.CIFailure },
		"ci pending":        func(f *Facts) { f.CI = github.CIPending },
	} {
		t.Run(name, func(t *testing.T) {
			f := eligibleFacts()
			mutate(&f)
			ok, reason := Eligible(f)
			require.False(t, ok)
			require.NotEmpty(t, reason)
		})
	}
}
