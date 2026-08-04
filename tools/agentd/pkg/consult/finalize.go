package consult

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/workspace"
)

// Finalize implements escalate.Finalizer: finalizing state (terminal target
// persisted in the event payload for crash replay), transcript export,
// workspace cleanup, then the terminal transition. Export and cleanup are
// best-effort and never block the finish.
func (r *Runner) Finalize(_ context.Context, jobID int64, state, outcome, summary string) error {
	payload, err := json.Marshal(map[string]string{"state": state, "outcome": outcome, "summary": summary})
	if err != nil {
		return err
	}
	if err := r.Store.SetJobState(jobID, "finalizing"); err != nil {
		return err
	}
	if err := r.Store.AddEvent(jobID, "finalizing", string(payload)); err != nil {
		return err
	}
	r.exportTranscript(jobID)
	r.cleanup(jobID)
	return r.Store.FinishJob(jobID, state, outcome, summary)
}

func (r *Runner) exportTranscript(jobID int64) {
	job, err := r.Store.GetJob(jobID)
	if err != nil || job.SessionID == "" {
		return
	}
	out, err := r.OC.Export(r.base, job.SessionID)
	if err != nil {
		_ = r.Store.AddEvent(jobID, "transcript_export_failed", fmt.Sprintf(`{"error":%q}`, firstLine(err.Error())))
		return
	}
	art := r.WS.ArtifactDir(jobID)
	if err := os.MkdirAll(art, 0o755); err != nil {
		return
	}
	path := filepath.Join(art, "transcript.json")
	if err := os.WriteFile(path, []byte(out), 0o644); err != nil {
		return
	}
	_ = r.Store.AddArtifact(jobID, "transcript.json", path)
}

func (r *Runner) cleanup(jobID int64) {
	job, err := r.Store.GetJob(jobID)
	if err != nil || job.WorktreePath == "" {
		return
	}
	err = r.WS.Cleanup(r.base, job.WorktreePath, r.Locals[job.Repo])
	if err == nil {
		return
	}
	// Dedupe against the job's open escalation so a finalize replayed after
	// a crash cannot spam the inbox with duplicate attention items.
	if _, open, escErr := r.Store.OpenEscalationForJob(jobID); escErr == nil && open {
		return
	}
	var dirty *workspace.DirtyError
	if errors.As(err, &dirty) {
		_ = r.Esc.Attention(jobID, fmt.Sprintf(
			"workspace has uncommitted changes: %s — `agentd gc --job %d --force` removes it", dirty.Dir, jobID))
		return
	}
	_ = r.Esc.Attention(jobID, fmt.Sprintf("workspace cleanup failed: %v", err))
}

// Continue implements escalate.Continuer: the job returns to running and the
// session resumes headless with the operator's answer.
func (r *Runner) Continue(_ context.Context, jobID int64, answer string) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if job.SessionID == "" {
		return fmt.Errorf("job %d has no registered session to continue", jobID)
	}
	if err := r.Store.SetJobState(jobID, "running"); err != nil {
		return err
	}
	if err := r.Store.AddEvent(jobID, "answered", ""); err != nil {
		return err
	}
	req := Request{JobID: jobID, Repo: job.Repo, Number: job.PRNumber}
	prompt := "Operator answer to your escalation:\n\n" + answer +
		"\n\nContinue the consult and finish with the report tool."
	r.spawnSession(req, job.WorktreePath, job.SessionID, prompt,
		"did not conclude after the operator's answer")
	return nil
}

// spawnSession resumes a session asynchronously; failPhase names the phase in
// the escalation raised when the session ends without a result.
func (r *Runner) spawnSession(req Request, dir, sessionID, prompt, failPhase string) {
	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		r.sem <- struct{}{}
		defer func() { <-r.sem }()
		out, err := r.OC.Run(r.base, opencode.Request{
			Dir: dir, Env: r.jobEnv(req.JobID), SessionID: sessionID, Prompt: prompt,
		})
		r.afterExit(req, dir, out, err, true, failPhase)
	}()
}

// Reconcile recovers consult jobs interrupted by a daemon restart, then
// sweeps orphaned workspaces.
func (r *Runner) Reconcile(onRestart string) error {
	prep, err := r.Store.JobsInState("preparing")
	if err != nil {
		return err
	}
	for _, j := range prep {
		if err := r.Store.FailJob(j.ID, "interrupted during preparation by daemon restart"); err != nil {
			return err
		}
	}
	running, err := r.Store.JobsInState("running")
	if err != nil {
		return err
	}
	for _, j := range running {
		if onRestart == "resume" && j.SessionID != "" {
			if err := r.Store.AddEvent(j.ID, "resumed_after_restart", ""); err != nil {
				return err
			}
			req := Request{JobID: j.ID, Repo: j.Repo, Number: j.PRNumber}
			r.spawnSession(req, j.WorktreePath, j.SessionID,
				"The daemon restarted while you were working. Continue the consult and "+
					"finish with the report tool, or the escalate tool if you need operator input.",
				"did not conclude after daemon restart")
			continue
		}
		if err := r.Store.FailJob(j.ID, "consult subprocess lost in daemon restart"); err != nil {
			return err
		}
	}
	finalizing, err := r.Store.JobsInState("finalizing")
	if err != nil {
		return err
	}
	for _, j := range finalizing {
		payload, ok, err := r.Store.LatestEventPayload(j.ID, "finalizing")
		if err != nil {
			return err
		}
		target := map[string]string{"state": "done", "outcome": "acted", "summary": "finalize replayed after restart"}
		if ok {
			_ = json.Unmarshal([]byte(payload), &target)
		}
		if err := r.Finalize(context.Background(), j.ID, target["state"], target["outcome"], target["summary"]); err != nil {
			return err
		}
	}
	if err := r.SweepInteractive(); err != nil {
		return err
	}
	removed, problems := r.GCAll()
	for _, p := range problems {
		r.Log.Warn("gc sweep", "problem", p)
	}
	if len(removed) > 0 {
		r.Log.Info("gc sweep", "removed", removed)
	}
	return nil
}

// GCAll sweeps workspaces whose jobs are terminal or missing.
func (r *Runner) GCAll() (removed []string, problems []string) {
	protected := map[int64]bool{}
	jobs, err := r.Store.NonTerminalJobs()
	if err != nil {
		return nil, []string{err.Error()}
	}
	locals := map[string]string{}
	for repo, local := range r.Locals {
		locals[projectName(repo)] = local
	}
	for _, j := range jobs {
		protected[j.ID] = true
	}
	return r.WS.Sweep(r.base, protected, locals)
}

// GCJob removes one job's workspace; force bypasses the dirty check.
func (r *Runner) GCJob(jobID int64, force bool) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if !isTerminal(job.State) && !force {
		return fmt.Errorf("job %d is %s; use --force to remove a live job's workspace", jobID, job.State)
	}
	if job.WorktreePath == "" {
		return nil
	}
	if err := r.WS.Remove(r.base, job.WorktreePath, r.Locals[job.Repo], force); err != nil {
		return err
	}
	return r.Store.AddEvent(jobID, "workspace_removed", "")
}
