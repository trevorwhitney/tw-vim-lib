// Package actor executes policy actions through the github.Writer interface.
// It is the only agentd code that performs writes against GitHub.
package actor

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

type Actor struct {
	Store  *store.Store
	GH     github.Writer
	DryRun bool
	Sleep  func(time.Duration)
}

const maxAttempts = 3

// Execute performs act for job. A previously executed (job, kind, params)
// action is not re-run; its recorded result is returned. shadow (or the
// global DryRun) records the action as simulated without calling the writer;
// the result names which mode ("shadow" or "dry-run").
func (a *Actor) Execute(ctx context.Context, jobID int64, act policy.Action, shadow bool) (string, error) {
	if err := validKind(act.Kind); err != nil {
		return "", err
	}
	params, err := json.Marshal(act.Params)
	if err != nil {
		return "", err
	}
	rec, executed, err := a.Store.UpsertAction(jobID, act.Kind, string(params))
	if err != nil {
		return "", err
	}
	if executed {
		return rec.Result, nil
	}

	if shadow || a.DryRun {
		mode := "shadow"
		if a.DryRun {
			mode = "dry-run"
		}
		if err := a.Store.MarkActionExecuted(rec.ID, mode, true); err != nil {
			return "", err
		}
		return mode, nil
	}

	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			a.Sleep(time.Duration(attempt) * 10 * time.Second)
		}
		out, err := a.dispatch(ctx, act)
		if err == nil {
			if err := a.Store.MarkActionExecuted(rec.ID, out, false); err != nil {
				return "", err
			}
			return out, nil
		}
		lastErr = err
	}
	_ = a.Store.MarkActionFailed(rec.ID, lastErr.Error())
	return "", fmt.Errorf("%s failed after %d attempts: %w", act.Kind, maxAttempts, lastErr)
}

func validKind(kind string) error {
	switch kind {
	case "merge_pr", "approve_pr", "comment_pr":
		return nil
	}
	return fmt.Errorf("unknown action kind %q", kind)
}

func (a *Actor) dispatch(ctx context.Context, act policy.Action) (string, error) {
	p := act.Params
	number, err := strconv.Atoi(p["number"])
	if err != nil {
		return "", fmt.Errorf("action %s: invalid pr number %q", act.Kind, p["number"])
	}
	switch act.Kind {
	case "merge_pr":
		return a.GH.MergePR(ctx, p["repo"], number, p["method"])
	case "approve_pr":
		return a.GH.ApprovePR(ctx, p["repo"], number)
	case "comment_pr":
		return a.GH.CommentPR(ctx, p["repo"], number, p["body"])
	}
	return "", validKind(act.Kind)
}
