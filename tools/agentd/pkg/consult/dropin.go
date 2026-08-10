package consult

import (
	"fmt"
)

// DropIn materializes a tmux window for the operator to drive the consult
// session interactively. The daemon stops managing the job until hand-back.
func (r *Runner) DropIn(jobID int64) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	switch job.State {
	case "waiting_input", "waiting_approval", "parked":
	default:
		return fmt.Errorf("job %d is %s; only waiting or parked jobs support drop-in", jobID, job.State)
	}
	if job.SessionID == "" {
		return fmt.Errorf("job %d has no registered session to drop into", jobID)
	}
	if job.WorktreePath == "" {
		return fmt.Errorf("job %d has no workspace", jobID)
	}
	if r.Tmux == nil {
		return fmt.Errorf("tmux controller not configured")
	}
	if err := r.Tmux.EnsureSession(r.Session); err != nil {
		return err
	}
	command := r.DropinCommand
	if command == "" {
		command = `nvim "+AgentFullscreen opencode"`
	}
	windowID, err := r.Tmux.NewWindow(r.Session, fmt.Sprintf("agentd-%d", jobID), job.WorktreePath,
		map[string]string{"AGENTD_SESSION_ID": job.SessionID}, command)
	if err != nil {
		return err
	}
	if err := r.Store.SetJobWindowID(jobID, windowID); err != nil {
		return err
	}
	if err := r.Store.AddEvent(jobID, "dropin", fmt.Sprintf(`{"window_id":%q}`, windowID)); err != nil {
		return err
	}
	return r.Store.SetJobState(jobID, "interactive")
}

// Handback reclaims an interactive job: close the window, resolve the open
// escalation as handled, finalize. finMu serializes this against the other
// terminal-side transitions (see the finMu field comment).
func (r *Runner) Handback(jobID int64) error {
	r.finMu.Lock()
	defer r.finMu.Unlock()
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if job.State != "interactive" {
		return fmt.Errorf("job %d is %s, not interactive", jobID, job.State)
	}
	if job.WindowID != "" && r.Tmux != nil {
		_ = r.Tmux.KillWindow(job.WindowID)
	}
	if err := r.Store.AddEvent(jobID, "handback", ""); err != nil {
		return err
	}
	if esc, ok, err := r.Store.OpenEscalationForJob(jobID); err == nil && ok {
		if err := r.Store.ResolveEscalation(esc.ID, "done", "resolved interactively", ""); err != nil {
			return err
		}
		_ = r.Esc.RefreshBadge()
	}
	return r.finalizeLocked(jobID, "done", "handled", "resolved interactively by operator")
}

// SweepInteractive treats interactive jobs whose drop-in window disappeared
// as implicit hand-backs.
func (r *Runner) SweepInteractive() error {
	if r.Tmux == nil {
		return nil
	}
	jobs, err := r.Store.JobsInState("interactive")
	if err != nil {
		return err
	}
	for _, j := range jobs {
		if j.WindowID == "" {
			continue
		}
		exists, err := r.Tmux.HasWindow(j.WindowID)
		if err != nil {
			r.Log.Warn("interactive sweep", "job", j.ID, "err", err)
			continue
		}
		if !exists {
			if err := r.Handback(j.ID); err != nil {
				r.Log.Error("implicit handback", "job", j.ID, "err", err)
			}
		}
	}
	return nil
}
