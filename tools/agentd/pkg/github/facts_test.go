package github

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_GetPR(t *testing.T) {
	fe := newFakeExec()
	fe.responses["pr view 7"] = `{"number":7,"title":"t","isDraft":true,
		"headRefOid":"s7","author":{"login":"alice"}}`
	c := New(fe.run)

	pr, err := c.GetPR("a/b", 7)
	require.NoError(t, err)
	require.Equal(t, PR{Number: 7, Title: "t", Draft: true, HeadSHA: "s7", Author: "alice"}, pr)
}

func Test_Facts(t *testing.T) {
	for name, tc := range map[string]struct {
		json string
		want Facts
	}{
		"all green": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}`,
			want: Facts{CI: CISuccess, Mergeable: MergeClean},
		},
		"no checks at all": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[]}`,
			want: Facts{CI: CISuccess, Mergeable: MergeClean},
		},
		"check failed": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}`,
			want: Facts{CI: CIFailure, Mergeable: MergeClean},
		},
		"legacy status context failure": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"StatusContext","state":"FAILURE"}]}`,
			want: Facts{CI: CIFailure, Mergeable: MergeClean},
		},
		"still running": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""}]}`,
			want: Facts{CI: CIPending, Mergeable: MergeClean},
		},
		"neutral and skipped pass": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"}]}`,
			want: Facts{CI: CISuccess, Mergeable: MergeClean},
		},
		"conflicting": {
			json: `{"mergeable":"CONFLICTING","statusCheckRollup":[]}`,
			want: Facts{CI: CISuccess, Mergeable: MergeDirty},
		},
		"mergeability unknown": {
			json: `{"mergeable":"UNKNOWN","statusCheckRollup":[]}`,
			want: Facts{CI: CISuccess, Mergeable: MergeUnknown},
		},
	} {
		t.Run(name, func(t *testing.T) {
			fe := newFakeExec()
			fe.responses["pr view 1"] = tc.json
			c := New(fe.run)
			facts, err := c.Facts("a/b", 1)
			require.NoError(t, err)
			require.Equal(t, tc.want, facts)
		})
	}
}

func Test_ChangedFiles(t *testing.T) {
	fe := newFakeExec()
	fe.responses["api --paginate"] = "go.mod\ngo.sum\nvendor/github.com/x/y.go\n"
	c := New(fe.run)

	files, truncated, err := c.ChangedFiles("a/b", 1)
	require.NoError(t, err)
	require.Equal(t, []string{"go.mod", "go.sum", "vendor/github.com/x/y.go"}, files)
	require.False(t, truncated)
}

func Test_ChangedFiles_EmptyPR(t *testing.T) {
	fe := newFakeExec()
	fe.responses["api --paginate"] = "\n"
	c := New(fe.run)

	files, truncated, err := c.ChangedFiles("a/b", 1)
	require.NoError(t, err)
	require.Empty(t, files)
	require.False(t, truncated)
}
