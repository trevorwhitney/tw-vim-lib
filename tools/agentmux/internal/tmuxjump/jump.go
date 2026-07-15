package tmuxjump

import (
	"fmt"
	"os/exec"
	"strings"
)

// Runner abstracts tmux/workmux invocations so Jump is unit-testable.
type Runner interface {
	// ListPanes returns lines of "<window_id> <pane_current_path>".
	ListPanes() (string, error)
	SelectWindow(windowID string) error
	WorkmuxOpen(handle string) error
}

// resolve finds the window id whose pane path equals path or is a subdirectory
// of it. First match wins. Empty string if none.
func resolve(listing, path string) string {
	for _, line := range strings.Split(listing, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, " ", 2)
		if len(fields) != 2 {
			continue
		}
		id, panePath := fields[0], fields[1]
		if panePath == path || strings.HasPrefix(panePath, path+"/") {
			return id
		}
	}
	return ""
}

// Jump focuses the tmux window for a worktree, resolving by pane path (never by
// window name). Falls back to `workmux open <handle>` then re-resolves. Returns
// an error only when the worktree can neither be found nor opened.
func Jump(path, handle string, r Runner) error {
	listing, listErr := r.ListPanes()
	if listErr == nil {
		if id := resolve(listing, path); id != "" {
			if err := r.SelectWindow(id); err != nil {
				return fmt.Errorf("select window %s: %w", id, err)
			}
			return nil
		}
	}
	if err := r.WorkmuxOpen(handle); err != nil {
		errMsg := fmt.Errorf("worktree %q not open and workmux open failed: %w", handle, err)
		if listErr != nil {
			return fmt.Errorf("%v (initial list error: %v)", errMsg, listErr)
		}
		return errMsg
	}
	listing, err := r.ListPanes()
	if err != nil {
		return fmt.Errorf("re-list panes after open: %w", err)
	}
	if id := resolve(listing, path); id != "" {
		if err := r.SelectWindow(id); err != nil {
			return fmt.Errorf("select window %s: %w", id, err)
		}
		return nil
	}
	errMsg := fmt.Errorf("worktree %q still not found after workmux open", handle)
	if listErr != nil {
		return fmt.Errorf("%v (initial list error: %v)", errMsg, listErr)
	}
	return errMsg
}

// ExecRunner runs real tmux/workmux commands.
type ExecRunner struct{}

func (ExecRunner) ListPanes() (string, error) {
	out, err := exec.Command("tmux", "list-panes", "-a", "-F", "#{window_id} #{pane_current_path}").Output()
	if err != nil {
		return "", fmt.Errorf("tmux list-panes: %w", err)
	}
	return string(out), nil
}
func (ExecRunner) SelectWindow(windowID string) error {
	out, err := exec.Command("tmux", "select-window", "-t", windowID).CombinedOutput()
	if err != nil {
		return fmt.Errorf("tmux select-window -t %s: %w: %s", windowID, err, strings.TrimSpace(string(out)))
	}
	return nil
}
func (ExecRunner) WorkmuxOpen(handle string) error {
	out, err := exec.Command("workmux", "open", handle).CombinedOutput()
	if err != nil {
		return fmt.Errorf("workmux open %s: %w: %s", handle, err, strings.TrimSpace(string(out)))
	}
	return nil
}
