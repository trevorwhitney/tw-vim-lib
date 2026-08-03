// Package workspace manages daemon-owned job directories: per-job artifact
// dirs, git-initialized scratch dirs, and worktrees added from a configured
// local checkout. Removal is never forced unless explicitly requested.
package workspace

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

type Manager struct {
	StateDir string // e.g. ~/.local/state/agentd
	Exec     execx.Runner
}

// DirtyError reports a workspace with uncommitted changes that non-forced
// cleanup refused to remove.
type DirtyError struct{ Dir string }

func (e *DirtyError) Error() string { return "workspace has uncommitted changes: " + e.Dir }

func (m *Manager) ArtifactDir(jobID int64) string {
	return filepath.Join(m.StateDir, "jobs", strconv.FormatInt(jobID, 10))
}

func (m *Manager) ScratchDir(jobID int64) string {
	return filepath.Join(m.ArtifactDir(jobID), "scratch")
}

func (m *Manager) WorktreeDir(project string, jobID int64) string {
	return filepath.Join(m.StateDir, "worktrees", project, strconv.FormatInt(jobID, 10))
}

// PrepareScratch creates the job's scratch dir as a git repository with one
// empty commit, so tooling that assumes a repo works and `git status` starts
// clean.
func (m *Manager) PrepareScratch(ctx context.Context, jobID int64) (string, error) {
	dir := m.ScratchDir(jobID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	for _, args := range [][]string{
		{"init"},
		{"-c", "user.email=agentd@localhost", "-c", "user.name=agentd",
			"commit", "--allow-empty", "--no-gpg-sign", "-m", "agentd job " + strconv.FormatInt(jobID, 10)},
	} {
		if out, err := m.Exec(ctx, execx.Options{Dir: dir}, "git", args...); err != nil {
			return "", fmt.Errorf("scratch init: %w: %s", err, out)
		}
	}
	return dir, nil
}

// PrepareWorktree fetches the PR head into the local checkout and adds a
// detached worktree for it under the daemon's worktree root.
func (m *Manager) PrepareWorktree(ctx context.Context, local, project string, jobID int64, prNumber int) (string, error) {
	dir := m.WorktreeDir(project, jobID)
	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return "", err
	}
	ref := fmt.Sprintf("refs/agentd/%d", jobID)
	fetch := fmt.Sprintf("refs/pull/%d/head:%s", prNumber, ref)
	if out, err := m.Exec(ctx, execx.Options{Dir: local}, "git", "fetch", "origin", fetch); err != nil {
		// The test seam seeds refs/pull/<n>/head directly; fall back to it
		// when there is no origin to fetch from.
		if out2, err2 := m.Exec(ctx, execx.Options{Dir: local}, "git", "update-ref", ref, fmt.Sprintf("refs/pull/%d/head", prNumber)); err2 != nil {
			return "", fmt.Errorf("fetch pr head: %w: %s / %s", err, out, out2)
		}
	}
	if out, err := m.Exec(ctx, execx.Options{Dir: local}, "git", "worktree", "add", "--detach", dir, ref); err != nil {
		return "", fmt.Errorf("worktree add: %w: %s", err, out)
	}
	return dir, nil
}

func (m *Manager) isDirty(ctx context.Context, dir string) bool {
	out, err := m.Exec(ctx, execx.Options{Dir: dir}, "git", "status", "--porcelain")
	if err != nil {
		return true
	}
	return strings.TrimSpace(out) != ""
}

// Cleanup removes a workspace directory, refusing with DirtyError when it has
// uncommitted changes. local, when non-empty, is the checkout whose worktree
// metadata should be pruned afterwards.
func (m *Manager) Cleanup(ctx context.Context, dir, local string) error {
	return m.remove(ctx, dir, local, false)
}

// Remove is Cleanup with an explicit force switch (gc --force).
func (m *Manager) Remove(ctx context.Context, dir, local string, force bool) error {
	return m.remove(ctx, dir, local, force)
}

func (m *Manager) remove(ctx context.Context, dir, local string, force bool) error {
	if dir == "" {
		return nil
	}
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return nil
	}
	if !force && m.isDirty(ctx, dir) {
		return &DirtyError{Dir: dir}
	}
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if local != "" {
		_, _ = m.Exec(ctx, execx.Options{Dir: local}, "git", "worktree", "prune")
	}
	return nil
}

// Sweep removes scratch dirs and worktrees whose job ids are not in
// protected. Artifact dirs are never touched. Failures are reported, not
// fatal; dirty leftovers stay put and appear in problems.
func (m *Manager) Sweep(ctx context.Context, protected map[int64]bool, locals map[string]string) (removed []string, problems []string) {
	jobsRoot := filepath.Join(m.StateDir, "jobs")
	for _, entry := range readDir(jobsRoot) {
		jobID, err := strconv.ParseInt(entry, 10, 64)
		if err != nil || protected[jobID] {
			continue
		}
		scratch := m.ScratchDir(jobID)
		if _, err := os.Stat(scratch); os.IsNotExist(err) {
			continue
		}
		if err := m.remove(ctx, scratch, "", false); err != nil {
			problems = append(problems, fmt.Sprintf("job %d: %v", jobID, err))
			continue
		}
		removed = append(removed, scratch)
	}
	wtRoot := filepath.Join(m.StateDir, "worktrees")
	for _, project := range readDir(wtRoot) {
		for _, entry := range readDir(filepath.Join(wtRoot, project)) {
			jobID, err := strconv.ParseInt(entry, 10, 64)
			if err != nil || protected[jobID] {
				continue
			}
			dir := m.WorktreeDir(project, jobID)
			if err := m.remove(ctx, dir, locals[project], false); err != nil {
				problems = append(problems, fmt.Sprintf("job %d: %v", jobID, err))
				continue
			}
			removed = append(removed, dir)
		}
	}
	return removed, problems
}

func readDir(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	return names
}
