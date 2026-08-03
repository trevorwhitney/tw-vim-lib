// Package execx is the subprocess seam for the gh client.
package execx

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

type Execer func(ctx context.Context, name string, args ...string) (string, error)

// Command runs name with args, returning combined output; errors carry the
// trailing output for context.
func Command(ctx context.Context, name string, args ...string) (string, error) {
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w: %s",
			name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// Options controls where and with what extra environment a subprocess runs.
// Env entries are appended to the parent environment.
type Options struct {
	Dir string
	Env map[string]string
}

// Runner is the subprocess seam for components that need cwd/env control
// (workspace, consult runner, tmux).
type Runner func(ctx context.Context, opts Options, name string, args ...string) (string, error)

// Run executes name with args, returning combined output; errors carry the
// trailing output for context.
func Run(ctx context.Context, opts Options, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = opts.Dir
	if len(opts.Env) > 0 {
		env := os.Environ()
		keys := make([]string, 0, len(opts.Env))
		for k := range opts.Env {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			env = append(env, k+"="+opts.Env[k])
		}
		cmd.Env = env
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w: %s",
			name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}
