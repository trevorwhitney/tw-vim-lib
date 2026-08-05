package engine

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/checks"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// PollAll runs one pass over every configured repository, then sweeps
// escalations and interactive windows. A repo that returned an auth error is skipped until restart.
func (e *Engine) PollAll(ctx context.Context) {
	if e.Paused() {
		return
	}
	for _, repo := range e.repos() {
		chain, ok := e.chainSnapshot(repo)
		if !ok {
			continue
		}
		e.mu.Lock()
		st := e.statusLocked(repo)
		skip := st.AuthError
		e.mu.Unlock()
		if skip {
			continue
		}
		err := e.pollRepo(ctx, repo, chain)
		e.mu.Lock()
		st.LastPollTS = time.Now().Unix()
		st.LastError = ""
		if err != nil {
			st.LastError = err.Error()
			var ae *github.AuthError
			if errors.As(err, &ae) {
				st.AuthError = true
			}
		}
		e.mu.Unlock()
		if err != nil {
			e.Log.Error("poll repo", "repo", repo, "err", err)
		}
	}
	if err := e.Esc.Sweep(); err != nil {
		e.Log.Error("escalation sweep", "err", err)
	}
	if e.Consult != nil {
		if err := e.Consult.SweepInteractive(); err != nil {
			e.Log.Error("interactive sweep", "err", err)
		}
	}
}

func (e *Engine) pollRepo(ctx context.Context, repo string, chain []policy.WithMeta) error {
	prs, err := e.GH.ListOpenPRs(repo)
	if err != nil {
		return err
	}
	for _, pr := range prs {
		if err := e.ProcessPR(ctx, repo, pr, chain); err != nil {
			e.Log.Error("process pr", "repo", repo, "pr", pr.Number, "err", err)
		}
	}
	return nil
}

// Once performs startup reconciliation and a single poll pass.
func (e *Engine) Once(ctx context.Context) error {
	if err := e.Reconcile(ctx); err != nil {
		return err
	}
	e.PollAll(ctx)
	if e.Consult != nil {
		e.Consult.Wait()
	}
	return nil
}

// Serve polls on interval until ctx is cancelled.
func (e *Engine) Serve(ctx context.Context, interval time.Duration) error {
	if err := e.Reconcile(ctx); err != nil {
		return err
	}
	e.PollAll(ctx)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			e.PollAll(ctx)
		}
	}
}

// Reconcile finishes work interrupted by a crash: queued jobs are failed (the
// retry path can rerun them) and the badge is refreshed via a sweep.
func (e *Engine) Reconcile(ctx context.Context) error {
	jobs, err := e.Store.JobsInState("queued")
	if err != nil {
		return err
	}
	for _, j := range jobs {
		if err := e.Store.FailJob(j.ID, "interrupted by daemon restart"); err != nil {
			return err
		}
	}
	if e.Consult != nil {
		if err := e.Consult.Reconcile(e.OnRestart); err != nil {
			return err
		}
	}
	return e.Esc.Sweep()
}

// EnqueuePR processes a single PR immediately, outside the poll loop.
func (e *Engine) EnqueuePR(ctx context.Context, repo string, number int) (store.Job, error) {
	chain, ok := e.chainSnapshot(repo)
	if !ok {
		return store.Job{}, fmt.Errorf("repo %q not configured", repo)
	}
	pr, err := e.GH.GetPR(repo, number)
	if err != nil {
		return store.Job{}, err
	}
	// An explicit enqueue is a request to re-evaluate now: the poller's
	// defer backoff must not suppress it.
	e.clearDeferred(fmt.Sprintf("%s#%d@%s", repo, number, pr.HeadSHA))
	if err := e.ProcessPR(ctx, repo, pr, chain); err != nil {
		return store.Job{}, err
	}
	job, ok, err := e.Store.JobForHead(repo, number, pr.HeadSHA, "pr")
	if err != nil {
		return store.Job{}, err
	}
	if !ok {
		return store.Job{}, fmt.Errorf("PR %s#%d was deferred by universal checks", repo, number)
	}
	return job, nil
}

// Retry re-evaluates a failed job whose head still matches the live PR and
// which still passes universal checks against freshly fetched facts. A
// refused retry leaves the job untouched.
func (e *Engine) Retry(ctx context.Context, jobID int64) (store.Job, error) {
	job, err := e.Store.GetJob(jobID)
	if err != nil {
		return store.Job{}, err
	}
	if job.State != "failed" {
		return store.Job{}, fmt.Errorf("job %d is %s; only failed jobs can be retried", jobID, job.State)
	}
	chain, ok := e.chainSnapshot(job.Repo)
	if !ok {
		return store.Job{}, fmt.Errorf("repo %q no longer configured", job.Repo)
	}
	pr, err := e.GH.GetPR(job.Repo, job.PRNumber)
	if err != nil {
		return store.Job{}, err
	}
	if pr.HeadSHA != job.HeadSHA {
		return store.Job{}, fmt.Errorf("head moved from %s to %s; the new head will be picked up by the next poll",
			job.HeadSHA, pr.HeadSHA)
	}
	viewer, err := e.GH.Viewer()
	if err != nil {
		return store.Job{}, err
	}
	ghFacts, err := e.GH.Facts(job.Repo, pr.Number)
	if err != nil {
		return store.Job{}, err
	}
	facts := checks.Facts{PR: pr, Viewer: viewer, Facts: ghFacts}
	if ok, reason := checks.Eligible(facts, checks.Options{AllowOperatorPRs: e.AllowOperatorPRs}); !ok {
		return store.Job{}, fmt.Errorf("PR is currently ineligible (%s); retry later", reason)
	}
	files, truncated, err := e.GH.ChangedFiles(job.Repo, pr.Number)
	if err != nil {
		return store.Job{}, err
	}
	if err := e.Store.ResetJob(jobID); err != nil {
		return store.Job{}, err
	}
	if err := e.Store.AddEvent(jobID, "retried", ""); err != nil {
		return store.Job{}, err
	}
	in := e.policyInput(job.Repo, facts, files, truncated)
	if err := e.runChain(ctx, jobID, in, chain); err != nil {
		return store.Job{}, err
	}
	return e.Store.GetJob(jobID)
}

func (e *Engine) SetPaused(p bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.paused = p
}

func (e *Engine) Paused() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.paused
}

// Statuses returns a snapshot of per-repo poll state for every configured
// repo, in stable order.
func (e *Engine) Statuses() []RepoStatus {
	e.mu.Lock()
	defer e.mu.Unlock()
	out := make([]RepoStatus, 0, len(e.Chains))
	for repo := range e.Chains {
		out = append(out, *e.statusLocked(repo))
	}
	sortStatuses(out)
	return out
}

func (e *Engine) statusLocked(repo string) *RepoStatus {
	if e.statuses == nil {
		e.statuses = map[string]*RepoStatus{}
	}
	if e.statuses[repo] == nil {
		e.statuses[repo] = &RepoStatus{Repo: repo}
	}
	return e.statuses[repo]
}
