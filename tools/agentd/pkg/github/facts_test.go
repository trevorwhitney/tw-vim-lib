package github

import (
	"errors"
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
		"failure wins over earlier pending": {
			json: `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}`,
			want: Facts{CI: CIFailure, Mergeable: MergeClean},
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
			fe.errors["pr checks 1"] = errors.New("gh pr checks 1 --repo a/b --required --json bucket: exit status 1: no required checks reported on the 'x' branch")
			c := New(fe.run)
			facts, err := c.Facts("a/b", 1)
			require.NoError(t, err)
			require.Equal(t, tc.want, facts)
		})
	}
}

func Test_ChangedFiles(t *testing.T) {
	fe := newFakeExec()
	fe.responses["changedFiles"] = "3\n"
	fe.responses["api --paginate"] = "go.mod\ngo.sum\nvendor/github.com/x/y.go\n"
	c := New(fe.run)

	files, truncated, err := c.ChangedFiles("a/b", 1)
	require.NoError(t, err)
	require.Equal(t, []string{"go.mod", "go.sum", "vendor/github.com/x/y.go"}, files)
	require.False(t, truncated)
}

func Test_ChangedFiles_Truncated(t *testing.T) {
	fe := newFakeExec()
	fe.responses["changedFiles"] = "5\n"
	fe.responses["api --paginate"] = "go.mod\ngo.sum\nvendor/github.com/x/y.go\n"
	c := New(fe.run)

	_, truncated, err := c.ChangedFiles("a/b", 1)
	require.NoError(t, err)
	require.True(t, truncated, "shorter list than the PR's changedFiles count means the cap cut it")
}

func Test_ChangedFiles_Empty(t *testing.T) {
	fe := newFakeExec()
	fe.responses["changedFiles"] = "0\n"
	fe.responses["api --paginate"] = "\n"
	c := New(fe.run)

	files, truncated, err := c.ChangedFiles("a/b", 1)
	require.NoError(t, err)
	require.Empty(t, files)
	require.False(t, truncated)
}

func Test_Facts_RequiredChecks(t *testing.T) {
	rollupPending := `{"mergeable":"MERGEABLE","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""}]}`

	for name, tc := range map[string]struct {
		checksResponse string
		want           Facts
	}{
		"required pass while others pending": {
			checksResponse: `[{"bucket":"pass"},{"bucket":"skipping"}]`,
			want:           Facts{CI: CISuccess, Mergeable: MergeClean},
		},
		"required fail": {
			checksResponse: `[{"bucket":"fail"}]`,
			want:           Facts{CI: CIFailure, Mergeable: MergeClean},
		},
		"required cancel": {
			checksResponse: `[{"bucket":"cancel"}]`,
			want:           Facts{CI: CIFailure, Mergeable: MergeClean},
		},
		"required pending": {
			checksResponse: `[{"bucket":"pending"}]`,
			want:           Facts{CI: CIPending, Mergeable: MergeClean},
		},
		"fail wins over earlier pending": {
			checksResponse: `[{"bucket":"pending"},{"bucket":"fail"}]`,
			want:           Facts{CI: CIFailure, Mergeable: MergeClean},
		},
		"pending survives later pass": {
			checksResponse: `[{"bucket":"pending"},{"bucket":"pass"}]`,
			want:           Facts{CI: CIPending, Mergeable: MergeClean},
		},
		"unknown bucket counts as pending": {
			checksResponse: `[{"bucket":"mystery"},{"bucket":"pass"}]`,
			want:           Facts{CI: CIPending, Mergeable: MergeClean},
		},
		"empty required list falls back": {
			checksResponse: `[]`,
			want:           Facts{CI: CIPending, Mergeable: MergeClean},
		},
	} {
		t.Run(name, func(t *testing.T) {
			fe := newFakeExec()
			fe.responses["pr view 1"] = rollupPending
			fe.responses["pr checks 1"] = tc.checksResponse
			c := New(fe.run)
			facts, err := c.Facts("a/b", 1)
			require.NoError(t, err)
			require.Equal(t, tc.want, facts)
		})
	}
}

func Test_Facts_RequiredChecksErrorPropagation(t *testing.T) {
	fe := newFakeExec()
	fe.responses["pr view 1"] = `{"mergeable":"MERGEABLE","statusCheckRollup":[]}`
	fe.errors["pr checks 1"] = errors.New("dial tcp: connection refused")
	c := New(fe.run)

	_, err := c.Facts("a/b", 1)
	require.Error(t, err)
	require.Equal(t, "dial tcp: connection refused", err.Error())
}

func Test_Facts_RequiredChecksArgv(t *testing.T) {
	const argv = "pr checks 1 --repo a/b --required --json bucket"
	fe := newFakeExec()
	fe.responses["pr view 1"] = `{"mergeable":"MERGEABLE","statusCheckRollup":[]}`
	fe.responses[argv] = `[{"bucket":"pass"}]`
	c := New(fe.run)

	facts, err := c.Facts("a/b", 1)
	require.NoError(t, err)
	require.Equal(t, Facts{CI: CISuccess, Mergeable: MergeClean}, facts)
	require.Equal(t, 1, fe.calls[argv], "expected gh invocation %q", argv)
}
