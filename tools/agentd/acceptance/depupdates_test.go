//go:build acceptance

package acceptance

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

// prState returns the GitHub PR state string (OPEN, MERGED, CLOSED).
func prState(t *testing.T, repo string, pr int) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	out, err := execx.Command(ctx, "gh", "pr", "view", "-R", repo, strconv.Itoa(pr), "--json", "state", "-q", ".state")
	require.NoError(t, err)
	return strings.TrimSpace(out)
}

// depUpdatesPolicies builds the merge-dependency-updates policy YAML fragment
// for startDaemonWithPolicies (6-space indent). login is the allowed author;
// shadow toggles shadow mode; allowedPaths lists the paths the policy permits.
func depUpdatesPolicies(login string, shadow bool, allowedPaths []string) string {
	paths := ""
	for _, p := range allowedPaths {
		paths += fmt.Sprintf("\n          - %s", p)
	}
	shadowLine := ""
	if shadow {
		shadowLine = "\n        shadow: true"
	}
	return fmt.Sprintf(`      merge-dependency-updates:%s
        allowed_authors:
          - %s
        allowed_paths:%s`, shadowLine, login, paths)
}

func TestDepUpdatesShadowRecordsWithoutMerging(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	login := ghLogin(t)

	policies := depUpdatesPolicies(login, true, []string{"test.txt"})
	client, _, _ := startDaemonWithPolicies(t, sandbox, "report", policies)

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "done")
	require.Equal(t, "acted", job.Outcome)

	// Shadow mode must not merge the PR.
	require.Equal(t, "OPEN", prState(t, sandbox, pr))

	// Recorded action result must indicate shadow mode.
	detail, err := client.JobDetail(job.ID)
	require.NoError(t, err)
	require.NotEmpty(t, detail.Actions)
	require.Equal(t, "shadow", detail.Actions[0].Result)
}

func TestDepUpdatesArmedMergesPR(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	login := ghLogin(t)

	policies := depUpdatesPolicies(login, false, []string{"test.txt"})
	client, _, _ := startDaemonWithPolicies(t, sandbox, "report", policies)

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "done")
	require.Equal(t, "acted", job.Outcome)

	// Armed mode must merge the PR.
	require.Equal(t, "MERGED", prState(t, sandbox, pr))
}

func TestDepUpdatesEscalatesOutsideAllowedPaths(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	login := ghLogin(t)

	// test.txt is outside go.mod — policy must escalate.
	policies := depUpdatesPolicies(login, true, []string{"go.mod"})
	client, _, _ := startDaemonWithPolicies(t, sandbox, "report", policies)

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_approval")

	jobResp, err := client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc := *jobResp.Escalation
	require.Contains(t, esc.Question, "allowed paths")

	err = client.Resolve(esc.ID, "reject", "acceptance", "")
	require.NoError(t, err)

	waitForJob(t, client, sandbox, pr, "rejected")

	require.Equal(t, "OPEN", prState(t, sandbox, pr))
}
