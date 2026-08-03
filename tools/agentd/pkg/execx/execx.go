// Package execx is the subprocess seam for the gh client.
package execx

import (
	"context"
	"fmt"
	"os/exec"
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
