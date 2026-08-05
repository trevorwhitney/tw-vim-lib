//go:build acceptance

// Package acceptance drives the installed agentd end-to-end: real daemon,
// socket, git, tmux (isolated -L server), and GitHub PRs in a private
// sandbox repo, with opencode replaced by fake-opencode.sh.
package acceptance

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/api"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/config"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/tmuxctl"
)

// requireTools skips the suite unless gh (authenticated), git, tmux, and
// curl are available.
func requireTools(t *testing.T) {
	t.Helper()
	for _, tool := range []string{"gh", "git", "tmux", "curl"} {
		_, err := exec.LookPath(tool)
		if err != nil {
			t.Skipf("acceptance tests require %s", tool)
		}
	}
}

// ensureSandbox returns "<login>/agentd-acceptance", creating the private
// repo (gh repo create --private --add-readme) on first use.
func ensureSandbox(t *testing.T) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	loginOutput, err := execx.Command(ctx, "gh", "api", "user", "-q", ".login")
	require.NoError(t, err)
	login := strings.TrimSpace(loginOutput)

	repo := login + "/agentd-acceptance"

	_, err = execx.Command(ctx, "gh", "repo", "view", repo)
	if err == nil {
		return repo
	}
	// Repo doesn't exist, create it

	_, err = execx.Command(ctx, "gh", "repo", "create", repo, "--private", "--add-readme")
	require.NoError(t, err, "failed to create sandbox repo")

	return repo
}

// openPR pushes a uniquely-named branch with one trivial file change and
// opens a PR, registering cleanup (gh pr close --delete-branch). Returns
// the PR number once its facts are settled (mergeability computed, no
// pending third-party checks). Account-level scanners (GitGuardian)
// occasionally wedge IN_PROGRESS on a PR for many minutes; a wedged PR is
// closed and replaced with a fresh one, which scans fast.
func openPR(t *testing.T, repo string) int {
	t.Helper()
	for attempt := 1; ; attempt++ {
		pr := createPR(t, repo)
		if waitChecksSettled(t, repo, pr, 90*time.Second) {
			return pr
		}
		if attempt >= 3 {
			t.Fatalf("PR checks never settled after %d attempts", attempt)
		}
		t.Logf("PR %d checks wedged; retrying with a fresh PR", pr)
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		_, _ = execx.Command(ctx, "gh", "pr", "close", "-R", repo, strconv.Itoa(pr), "--delete-branch")
		cancel()
	}
}

func createPR(t *testing.T, repo string) int {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Clone repo into temp dir (gh resolves auth/protocol)
	tmpDir := filepath.Join(t.TempDir(), fmt.Sprintf("clone-%d", time.Now().UnixNano()))
	_, err := execx.Command(ctx, "gh", "repo", "clone", repo, tmpDir)
	require.NoError(t, err, "failed to clone repo")

	branch := fmt.Sprintf("test-%d", time.Now().UnixNano())
	_, err = execx.Run(ctx, execx.Options{Dir: tmpDir}, "git", "checkout", "-b", branch)
	require.NoError(t, err, "failed to create branch")

	testFile := filepath.Join(tmpDir, "test.txt")
	err = os.WriteFile(testFile, []byte("acceptance test "+branch+"\n"), 0o644)
	require.NoError(t, err, "failed to write test file")

	_, err = execx.Run(ctx, execx.Options{Dir: tmpDir}, "git", "add", "test.txt")
	require.NoError(t, err)
	_, err = execx.Run(ctx, execx.Options{Dir: tmpDir}, "git", "commit", "--no-gpg-sign", "-m", "acceptance test")
	require.NoError(t, err)
	_, err = execx.Run(ctx, execx.Options{Dir: tmpDir}, "git", "push", "-u", "origin", branch)
	require.NoError(t, err, "failed to push branch")

	output, err := execx.Command(ctx, "gh", "pr", "create", "-R", repo, "-B", "main", "-H", branch, "-t", "Test PR", "-b", "Acceptance test")
	require.NoError(t, err, "failed to create PR")

	// gh prints the PR URL last: https://github.com/owner/repo/pull/NUMBER
	parts := strings.Split(strings.TrimSpace(output), "/")
	prNumber, err := strconv.Atoi(parts[len(parts)-1])
	require.NoError(t, err, "failed to parse PR number from: %s", output)

	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_, _ = execx.Command(ctx, "gh", "pr", "close", "-R", repo, strconv.Itoa(prNumber), "--delete-branch")
	})

	return prNumber
}

// waitChecksSettled reports whether the PR's mergeability is computed and no
// check in the rollup is still running before the deadline.
func waitChecksSettled(t *testing.T, repo string, pr int, wait time.Duration) bool {
	t.Helper()
	deadline := time.Now().Add(wait)
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		out, err := execx.Command(ctx, "gh", "pr", "view", strconv.Itoa(pr), "-R", repo,
			"--json", "mergeable,statusCheckRollup",
			"-q", `[.mergeable] + [.statusCheckRollup[].status] | join(" ")`)
		cancel()
		if err == nil {
			fields := strings.Fields(out)
			settled := len(fields) > 0 && fields[0] != "UNKNOWN"
			for _, f := range fields[1:] {
				if f != "COMPLETED" {
					settled = false
				}
			}
			if settled {
				return true
			}
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(3 * time.Second)
	}
}

// startDaemon builds agentd, writes the acceptance config into a temp
// dir, starts `agentd serve`, waits for the socket, and registers cleanup
// (SIGTERM + tmux -L kill-server). Returns an api.Client, the config, and
// the state dir.
func startDaemon(t *testing.T, repo, fakeMode string) (*api.Client, *config.Config, string) {
	t.Helper()
	buildCtx, buildCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer buildCancel()

	// Build agentd binary once (cached in a stable location during the test)
	binDir := t.TempDir()
	binPath := filepath.Join(binDir, "agentd")
	_, err := execx.Run(buildCtx, execx.Options{Dir: filepath.Join(repoRoot(), "tools/agentd")}, "go", "build", "-o", binPath, "./cmd/agentd")
	require.NoError(t, err, "failed to build agentd")

	// Create state dir with short path to avoid unix socket length limit
	tmpDir := os.Getenv("TMPDIR")
	if tmpDir == "" {
		tmpDir = "/tmp"
	}
	stateDir, err := os.MkdirTemp(tmpDir, "agentd-test-")
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.RemoveAll(stateDir) })

	// Get absolute path to fake-opencode.sh
	shimPath := filepath.Join(repoRoot(), "tools/agentd/acceptance/fake-opencode.sh")
	shimPath, err = filepath.Abs(shimPath)
	require.NoError(t, err)

	// Write config as YAML text
	cfgPath := filepath.Join(stateDir, "config.yaml")
	cfgYAML := fmt.Sprintf(`poll_interval: 2s
concurrency: 1
database: %s
socket: %s
tmux_session: agentd-accept
tmux_socket_name: agentd-accept
opencode_bin: %s
dropin_command: "sleep 300"
allow_operator_prs: true
notify:
  banner: none
  badge_file: %s
repositories:
  - repo: %s
    policies:
      consult-triage:
        verdicts:
          approve:
            action: comment_pr
          needs-human:
            action: none
`,
		filepath.Join(stateDir, "agentd.db"),
		filepath.Join(stateDir, "agentd.sock"),
		shimPath,
		filepath.Join(stateDir, "badge"),
		repo,
	)
	err = os.WriteFile(cfgPath, []byte(cfgYAML), 0o644)
	require.NoError(t, err, "failed to write config")

	// Load config to verify
	cfg, err := config.Load(cfgPath)
	require.NoError(t, err, "failed to load config")

	// Start daemon with AGENTD_FAKE_MODE (with background context, not bounded)
	cmd := exec.CommandContext(context.Background(), binPath, "serve", "--config", cfgPath)
	cmd.Env = os.Environ()
	cmd.Env = append(cmd.Env, "AGENTD_FAKE_MODE="+fakeMode)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	err = cmd.Start()
	require.NoError(t, err, "failed to start daemon")

	// Wait for socket to be available and accepting connections
	socketPath := cfg.Socket
	deadline := time.Now().Add(15 * time.Second)
	for {
		// Check if process is still running
		if cmd.ProcessState != nil {
			t.Fatalf("daemon exited unexpectedly: %v", cmd.ProcessState)
		}

		conn, err := net.Dial("unix", socketPath)
		if err == nil {
			conn.Close()
			break
		}
		if time.Now().After(deadline) {
			cmd.Process.Kill()
			t.Fatal("daemon socket did not become available")
		}
		time.Sleep(200 * time.Millisecond)
	}
	// Give daemon extra time to fully start
	time.Sleep(3 * time.Second)

	// Create client (will be retried on first use)
	client := api.NewClient(socketPath)

	// Test socket is actually working
	deadlineHTTP := time.Now().Add(5 * time.Second)
	for {
		_, err := client.Status()
		if err == nil {
			break
		}
		if time.Now().After(deadlineHTTP) {
			cmd.Process.Kill()
			t.Fatalf("daemon socket not responding: %v", err)
		}
		time.Sleep(500 * time.Millisecond)
	}

	// Register cleanup
	t.Cleanup(func() {
		// Wait a bit before trying to kill to let daemon finish cleanly
		time.Sleep(500 * time.Millisecond)
		cmd.Process.Signal(os.Interrupt)
		done := make(chan error, 1)
		go func() {
			done <- cmd.Wait()
		}()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			cmd.Process.Kill()
			<-done
		}
		// Kill tmux server for this test
		_ = exec.Command("tmux", "-L", "agentd-accept", "kill-server").Run()
	})

	return client, cfg, stateDir
}

// waitForJob polls the daemon (api.Client Enqueue) to get the job ID for the PR
// and then polls until it reaches wantState, failing after 60s.
func waitForJob(t *testing.T, c *api.Client, repo string, pr int, wantState string) store.Job {
	t.Helper()

	// Enqueue the PR, with retries for deferred state. Mergeability takes a
	// few seconds to compute and account-level apps (GitGuardian) hold CI
	// pending for up to a minute — longer when the suite's PRs queue up
	// back-to-back.
	var job store.Job
	deadline := time.Now().Add(4 * time.Minute)
	for {
		var err error
		job, err = c.Enqueue(repo, pr)
		if err == nil && job.ID != 0 {
			break
		}
		// Deferred: facts not settled yet (mergeability, pending app checks).
		// UNIQUE constraint: the 2s poller won the insert race; the retry
		// returns the existing job.
		msg := fmt.Sprintf("%v", err)
		if strings.Contains(msg, "deferred") || strings.Contains(msg, "UNIQUE constraint") {
			if time.Now().After(deadline) {
				require.Fail(t, "PR never yielded a job", msg)
			}
			time.Sleep(2 * time.Second)
			continue
		}
		require.NoError(t, err)
		require.NotZero(t, job.ID)
		break
	}

	// Poll until the job reaches the desired state
	pollDeadline := time.Now().Add(60 * time.Second)
	for {
		jobResp, err := c.Job(job.ID)
		if err != nil {
			t.Logf("job check failed: %v", err)
		} else {
			if jobResp.Job.State == wantState {
				return jobResp.Job
			}
			t.Logf("job %d state=%s (want %s)", jobResp.Job.ID, jobResp.Job.State, wantState)
		}

		if time.Now().After(pollDeadline) {
			t.Fatalf("job did not reach %s after 60s", wantState)
		}
		time.Sleep(500 * time.Millisecond)
	}
}

// repoRoot returns the absolute path to the repo root.
func repoRoot() string {
	wd, _ := os.Getwd()
	// Find the repo root by looking for tools/agentd/acceptance
	for {
		if info, err := os.Stat(filepath.Join(wd, "tools/agentd/acceptance")); err == nil && info.IsDir() {
			return wd
		}
		parent := filepath.Dir(wd)
		if parent == wd {
			// Couldn't find repo root, return current working directory
			return wd
		}
		wd = parent
	}
}

func TestReportApprovalExecutesMappedAction(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	client, _, stateDir := startDaemon(t, sandbox, "report")

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_approval")
	require.NotZero(t, job.ID)

	// Resolve with approve
	var esc store.Escalation
	jobResp, err := client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc = *jobResp.Escalation

	err = client.Resolve(esc.ID, "approve", "acceptance", "")
	require.NoError(t, err)

	// Wait for done
	finalJob := waitForJob(t, client, sandbox, pr, "done")
	require.Equal(t, "acted", finalJob.Outcome)

	// Check that comment was posted
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	output, err := execx.Command(ctx, "gh", "pr", "view", "-R", sandbox, strconv.Itoa(pr), "--json", "comments", "-q", ".comments[0].body")
	require.NoError(t, err)
	require.Contains(t, output, "agentd")

	// Check artifacts
	require.FileExists(t, filepath.Join(stateDir, "jobs", strconv.FormatInt(job.ID, 10), "transcript.json"))
	require.FileExists(t, filepath.Join(stateDir, "jobs", strconv.FormatInt(job.ID, 10), "report.md"))
}

func TestRejectFinalizesWithoutWriting(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	client, _, _ := startDaemon(t, sandbox, "report")

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_approval")

	var esc store.Escalation
	jobResp, err := client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc = *jobResp.Escalation

	// Reject
	err = client.Resolve(esc.ID, "reject", "acceptance", "")
	require.NoError(t, err)

	// Wait for rejected
	finalJob := waitForJob(t, client, sandbox, pr, "rejected")
	require.NotZero(t, finalJob.ID)

	// Verify no comment was posted
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	output, err := execx.Command(ctx, "gh", "pr", "view", "-R", sandbox, strconv.Itoa(pr), "--json", "comments", "-q", ".comments | length")
	require.NoError(t, err)
	count := strings.TrimSpace(output)
	require.Equal(t, "0", count)
}

func TestEscalateAnswerContinuation(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	client, _, _ := startDaemon(t, sandbox, "escalate")

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_input")

	var esc store.Escalation
	jobResp, err := client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc = *jobResp.Escalation

	// Answer the question
	err = client.Resolve(esc.ID, "answer", "", "use main")
	require.NoError(t, err)

	// Wait for waiting_approval (after continuation)
	job = waitForJob(t, client, sandbox, pr, "waiting_approval")

	// Get new escalation
	jobResp, err = client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc = *jobResp.Escalation

	// Approve
	err = client.Resolve(esc.ID, "approve", "acceptance", "")
	require.NoError(t, err)

	// Wait for done
	finalJob := waitForJob(t, client, sandbox, pr, "done")
	require.Equal(t, "acted", finalJob.Outcome)
}

func TestDropinWindowLifecycle(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	client, _, _ := startDaemon(t, sandbox, "report")

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_approval")

	// Request dropin
	err := client.DropIn(job.ID)
	require.NoError(t, err)

	// Wait for interactive
	job = waitForJob(t, client, sandbox, pr, "interactive")
	require.NotEmpty(t, job.WindowID)

	// Check tmux window exists
	tmuxClient := &tmuxctl.Client{Exec: execx.Run, SocketName: "agentd-accept"}
	hasWindow, err := tmuxClient.HasWindow(job.WindowID)
	require.NoError(t, err)
	require.True(t, hasWindow)

	// Kill the window
	err = tmuxClient.KillWindow(job.WindowID)
	require.NoError(t, err)

	// Within one poll interval, job should be done (implicit hand-back)
	time.Sleep(3 * time.Second)
	finalJob := waitForJob(t, client, sandbox, pr, "done")
	require.NotZero(t, finalJob.ID)
}

func TestGCSweep(t *testing.T) {
	requireTools(t)
	sandbox := ensureSandbox(t)
	client, _, _ := startDaemon(t, sandbox, "report")

	pr := openPR(t, sandbox)
	job := waitForJob(t, client, sandbox, pr, "waiting_approval")

	var esc store.Escalation
	jobResp, err := client.Job(job.ID)
	require.NoError(t, err)
	require.NotNil(t, jobResp.Escalation)
	esc = *jobResp.Escalation

	// Approve and wait for done
	err = client.Resolve(esc.ID, "approve", "acceptance", "")
	require.NoError(t, err)
	finalJob := waitForJob(t, client, sandbox, pr, "done")

	// Full sweep and targeted gc report no problems on a clean state dir.
	err = client.GC(0, false)
	require.NoError(t, err)
	err = client.GC(finalJob.ID, false)
	require.NoError(t, err)

	// Re-dirty the finished job's recorded workspace path.
	wsDir := finalJob.WorktreePath
	require.NotEmpty(t, wsDir)
	require.NoError(t, os.MkdirAll(wsDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(wsDir, "dirty.txt"), []byte("dirty"), 0o644))

	// Non-forced GC should refuse
	err = client.GC(finalJob.ID, false)
	require.Error(t, err, "non-forced GC should refuse dirty workspace")

	// Forced GC should work
	err = client.GC(finalJob.ID, true)
	require.NoError(t, err)

	// Workspace should be gone
	_, err = os.Stat(wsDir)
	require.True(t, os.IsNotExist(err))
}
