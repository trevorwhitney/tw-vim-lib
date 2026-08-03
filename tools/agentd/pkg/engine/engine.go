// Package engine wires poller facts, universal checks, the policy chain, the
// actor, and the escalation manager into the per-PR processing pipeline.
package engine

import (
	"context"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/checks"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// deferRecheck throttles fact fetches for heads already found ineligible;
// each read is a gh subprocess, so parked PRs should not be re-checked every
// poll.
const deferRecheck = 5 * time.Minute

type RepoStatus struct {
	Repo       string `json:"repo"`
	LastPollTS int64  `json:"last_poll_ts"`
	LastError  string `json:"last_error"`
	AuthError  bool   `json:"auth_error"`
}

type Engine struct {
	Store  *store.Store
	GH     github.Reader
	Actor  *actor.Actor
	Esc    *escalate.Manager
	Chains map[string][]policy.WithMeta
	Log    *slog.Logger

	mu       sync.Mutex
	paused   bool
	statuses map[string]*RepoStatus

	deferMu    sync.Mutex
	deferredAt map[string]time.Time
}

// ProcessPR evaluates one PR head. Ineligible PRs are deferred without a
// ledger record (re-checked after deferRecheck); a head already recorded for
// this repo/PR/kind is skipped.
func (e *Engine) ProcessPR(ctx context.Context, repo string, pr github.PR, chain []policy.WithMeta) error {
	seen, err := e.Store.HasJob(repo, pr.Number, pr.HeadSHA, "pr")
	if err != nil || seen {
		return err
	}
	key := fmt.Sprintf("%s#%d@%s", repo, pr.Number, pr.HeadSHA)
	if e.recentlyDeferred(key) {
		return nil
	}

	viewer, err := e.GH.Viewer()
	if err != nil {
		return err
	}
	ghFacts, err := e.GH.Facts(repo, pr.Number)
	if err != nil {
		return err
	}
	facts := checks.Facts{PR: pr, Viewer: viewer, Facts: ghFacts}
	if ok, reason := checks.Eligible(facts); !ok {
		e.markDeferred(key)
		e.Log.Debug("deferred", "repo", repo, "pr", pr.Number, "reason", reason)
		return nil
	}

	files, truncated, err := e.GH.ChangedFiles(repo, pr.Number)
	if err != nil {
		return err
	}
	jobID, err := e.Store.CreateJob("pr", repo, pr.Number, pr.HeadSHA)
	if err != nil {
		return err
	}
	return e.runChain(ctx, jobID, policyInput(repo, facts, files, truncated), chain)
}

func (e *Engine) runChain(ctx context.Context, jobID int64, in policy.Input, chain []policy.WithMeta) error {
	idx, res, trail, chainErr := policy.Chain(chain, in)
	for _, t := range trail {
		if err := e.Store.AddDecision(jobID, t.Policy, string(t.Verdict), t.Rationale); err != nil {
			return err
		}
	}
	if chainErr != nil {
		return e.Store.FailJob(jobID, chainErr.Error())
	}

	switch res.Verdict {
	case policy.Pass:
		return e.Store.FinishJob(jobID, "done", "skipped", "no policy applies")
	case policy.Act:
		if res.Action == nil {
			return e.Store.FailJob(jobID, "act verdict without action")
		}
		handler := chain[idx]
		out, err := e.Actor.Execute(ctx, jobID, *res.Action, handler.Shadow)
		if err != nil {
			question := fmt.Sprintf("action %s failed after retries: %v — approve to retry", res.Action.Kind, err)
			return e.Esc.Create(jobID, question, res.Rationale, res.Action)
		}
		summary := fmt.Sprintf("%s via %s: %s", res.Action.Kind, handler.Policy.Name(), firstLine(out))
		return e.Store.FinishJob(jobID, "done", "acted", summary)
	case policy.Escalate:
		return e.Esc.Create(jobID, res.Question, res.Rationale, res.Action)
	}
	return e.Store.FailJob(jobID, fmt.Sprintf("unknown verdict %q", res.Verdict))
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// policyInput assembles the chain input from gathered facts. Shared by
// ProcessPR and Retry.
func policyInput(repo string, facts checks.Facts, files []string, truncated bool) policy.Input {
	return policy.Input{
		Repo:           repo,
		Facts:          facts,
		Files:          files,
		FilesTruncated: truncated,
	}
}

func sortStatuses(s []RepoStatus) {
	slices.SortFunc(s, func(a, b RepoStatus) int { return strings.Compare(a.Repo, b.Repo) })
}

func (e *Engine) recentlyDeferred(key string) bool {
	e.deferMu.Lock()
	defer e.deferMu.Unlock()
	return time.Since(e.deferredAt[key]) < deferRecheck
}

func (e *Engine) markDeferred(key string) {
	e.deferMu.Lock()
	defer e.deferMu.Unlock()
	if e.deferredAt == nil {
		e.deferredAt = map[string]time.Time{}
	}
	e.deferredAt[key] = time.Now()
}
