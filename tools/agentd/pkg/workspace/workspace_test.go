package workspace

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

func mgr(t *testing.T) *Manager {
	t.Helper()
	return &Manager{StateDir: t.TempDir(), Exec: execx.Run}
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := execx.Run(context.Background(), execx.Options{Dir: dir}, "git", args...)
	require.NoError(t, err, out)
	return out
}

// seedRepo creates a git repo with one commit on main and returns its path.
func seedRepo(t *testing.T) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "repo")
	require.NoError(t, os.MkdirAll(dir, 0o755))
	git(t, dir, "init", "-b", "main")
	git(t, dir, "config", "user.email", "t@t")
	git(t, dir, "config", "user.name", "t")
	require.NoError(t, os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0o644))
	git(t, dir, "add", ".")
	git(t, dir, "commit", "-m", "init", "--no-gpg-sign")
	return dir
}

func TestPrepareScratchIsCleanGitRepo(t *testing.T) {
	m := mgr(t)
	dir, err := m.PrepareScratch(context.Background(), 7)
	require.NoError(t, err)
	require.Equal(t, m.ScratchDir(7), dir)

	out := git(t, dir, "status", "--porcelain")
	require.Empty(t, out, "fresh scratch must be clean")
}

func TestCleanupRemovesCleanScratch(t *testing.T) {
	m := mgr(t)
	dir, err := m.PrepareScratch(context.Background(), 7)
	require.NoError(t, err)

	require.NoError(t, m.Cleanup(context.Background(), dir, ""))
	_, statErr := os.Stat(dir)
	require.True(t, os.IsNotExist(statErr))
}

func TestCleanupRefusesDirtyWorkspace(t *testing.T) {
	m := mgr(t)
	dir, err := m.PrepareScratch(context.Background(), 7)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, "notes.md"), []byte("wip"), 0o644))

	err = m.Cleanup(context.Background(), dir, "")
	var dirty *DirtyError
	require.ErrorAs(t, err, &dirty)
	require.Equal(t, dir, dirty.Dir)
	_, statErr := os.Stat(dir)
	require.NoError(t, statErr, "dirty workspace must not be removed")

	require.NoError(t, m.Remove(context.Background(), dir, "", true), "forced removal succeeds")
	_, statErr = os.Stat(dir)
	require.True(t, os.IsNotExist(statErr))
}

func TestPrepareWorktree(t *testing.T) {
	local := seedRepo(t)
	sha := git(t, local, "rev-parse", "HEAD")
	m := mgr(t)

	// The runner fetches pull/<n>/head; simulate GitHub's ref layout locally.
	git(t, local, "update-ref", "refs/pull/5/head", sha[:40])

	dir, err := m.PrepareWorktree(context.Background(), local, "repo", 9, 5)
	require.NoError(t, err)
	require.Equal(t, m.WorktreeDir("repo", 9), dir)
	require.FileExists(t, filepath.Join(dir, "a.txt"))

	require.NoError(t, m.Cleanup(context.Background(), dir, local))
	_, statErr := os.Stat(dir)
	require.True(t, os.IsNotExist(statErr))
}

func TestSweep(t *testing.T) {
	m := mgr(t)
	_, err := m.PrepareScratch(context.Background(), 1)
	require.NoError(t, err)
	_, err = m.PrepareScratch(context.Background(), 2)
	require.NoError(t, err)
	dirty, err := m.PrepareScratch(context.Background(), 3)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dirty, "wip.md"), []byte("x"), 0o644))

	removed, problems := m.Sweep(context.Background(), map[int64]bool{2: true}, nil)
	require.Equal(t, []string{m.ScratchDir(1)}, removed, "only the unprotected clean scratch is removed")
	require.Len(t, problems, 1, "dirty orphan is reported, not removed")
	require.Contains(t, problems[0], strconv.Itoa(3))

	require.DirExists(t, m.ScratchDir(2), "protected scratch survives")
	require.DirExists(t, m.ScratchDir(3), "dirty scratch survives")
	require.DirExists(t, m.ArtifactDir(1), "artifact dir always survives")
}

func TestPrepareWorktreeFailsOnFetchErrorWithOrigin(t *testing.T) {
	local := seedRepo(t)
	ctx := context.Background()
	_, err := execx.Run(ctx, execx.Options{Dir: local}, "git", "remote", "add", "origin",
		filepath.Join(t.TempDir(), "missing.git"))
	require.NoError(t, err)
	// A stale ref the old fallback would have silently used.
	_, err = execx.Run(ctx, execx.Options{Dir: local}, "git", "update-ref", "refs/pull/5/head", "HEAD")
	require.NoError(t, err)

	m := &Manager{StateDir: t.TempDir(), Exec: execx.Run}
	_, err = m.PrepareWorktree(ctx, local, "proj", 7, 5)
	require.Error(t, err, "a transient fetch failure must not fall back to a stale local ref")
}
