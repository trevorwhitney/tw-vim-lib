package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func write(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(p, []byte(content), 0o644))
	return p
}

func Test_Load_DefaultsAndOrderedPolicies(t *testing.T) {
	dir := t.TempDir()
	p := write(t, dir, "config.yaml", `
repositories:
  - repo: grafana/loki
    policies:
      merge-dependency-updates:
        allowed_paths: ["go.mod", "go.sum"]
        shadow: true
      another-policy: {}
`)
	cfg, err := Load(p)
	require.NoError(t, err)
	require.Equal(t, time.Minute, time.Duration(cfg.PollInterval))
	require.Equal(t, 3, cfg.Concurrency)
	require.Equal(t, "decisions", cfg.Notify.Banner)
	require.Equal(t, 4*time.Hour, time.Duration(cfg.Escalation.RenotifyAfter))
	require.Equal(t, 24*time.Hour, time.Duration(cfg.Escalation.ParkAfter))
	require.Equal(t, "resume", cfg.OnRestart)
	require.Equal(t, "agents", cfg.TmuxSession)
	require.NotEmpty(t, cfg.Database)
	require.NotEmpty(t, cfg.Socket)
	require.Len(t, cfg.Repositories, 1)
	repo := cfg.Repositories[0]
	require.Equal(t, "grafana/loki", repo.Repo)
	require.Len(t, repo.Policies, 2)
	require.Equal(t, "merge-dependency-updates", repo.Policies[0].Name)
	require.Equal(t, "another-policy", repo.Policies[1].Name)
}

func Test_Load_RulesFile(t *testing.T) {
	dir := t.TempDir()
	rules := write(t, dir, "rules.yaml", `
repositories:
  - repo: grafana/mimir
    policies:
      merge-dependency-updates: {}
`)
	p := write(t, dir, "config.yaml", "rules: "+rules+"\n")
	cfg, err := Load(p)
	require.NoError(t, err)
	require.Len(t, cfg.Repositories, 1)
	require.Equal(t, "grafana/mimir", cfg.Repositories[0].Repo)
}

func Test_Load_Errors(t *testing.T) {
	dir := t.TempDir()
	rules := write(t, dir, "rules.yaml", "repositories:\n  - repo: a/b\n    policies:\n      x: {}\n")
	for name, content := range map[string]string{
		"both sources":     "rules: " + rules + "\nrepositories:\n  - repo: a/b\n    policies:\n      x: {}\n",
		"no repositories":  "poll_interval: 5m\n",
		"repo no policies": "repositories:\n  - repo: a/b\n",
		"bad banner":       "notify:\n  banner: sometimes\nrepositories:\n  - repo: a/b\n    policies:\n      x: {}\n",
		"bad on_restart":   "on_restart: explode\nrepositories:\n  - repo: a/b\n    policies:\n      x: {}\n",
		"bad duration":     "poll_interval: fast\nrepositories:\n  - repo: a/b\n    policies:\n      x: {}\n",
	} {
		t.Run(name, func(t *testing.T) {
			_, err := Load(write(t, dir, "c-"+name+".yaml", content))
			require.Error(t, err)
		})
	}
}
