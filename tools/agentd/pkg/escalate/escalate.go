// Package escalate manages the attention queue: creating escalations,
// applying human resolutions, and sweeping stale items.
package escalate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

var ErrUnsupportedResolution = errors.New("unsupported resolution (approve|reject|answer)")

// Finalizer runs a job's finalizing phase (transcript, cleanup) before the
// terminal transition. Nil falls back to a direct FinishJob.
type Finalizer interface {
	Finalize(ctx context.Context, jobID int64, state, outcome, summary string) error
}

// Continuer resumes a consult session headless with the operator's answer.
type Continuer interface {
	Continue(ctx context.Context, jobID int64, answer string) error
}

type Manager struct {
	Store         *store.Store
	Notify        *notify.Notifier
	RenotifyAfter time.Duration
	ParkAfter     time.Duration
	Now           func() time.Time
	Final         Finalizer
	Cont          Continuer
}

// Create records an escalation, parks the job in a waiting state, and
// notifies. kind may be empty: it is derived from the attached action
// (waiting_approval with one, waiting_input without).
func (m *Manager) Create(jobID int64, kind, question, advice string, act *policy.Action) error {
	actionKind, actionParams := "", ""
	if act != nil {
		actionKind = act.Kind
		b, err := json.Marshal(act.Params)
		if err != nil {
			return err
		}
		actionParams = string(b)
	}
	if kind == "" {
		kind = "waiting_input"
		if act != nil {
			kind = "waiting_approval"
		}
	}
	id, err := m.Store.CreateEscalation(jobID, kind, question, advice, actionKind, actionParams)
	if err != nil {
		return err
	}
	if err := m.Store.SetJobState(jobID, kind); err != nil {
		return err
	}
	job, err := m.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	m.Notify.EscalationCreated(kind, fmt.Sprintf("agentd: %s#%d", job.Repo, job.PRNumber), question)
	if err := m.Store.TouchEscalationNotified(id); err != nil {
		return err
	}
	return m.updateBadge()
}

// Attention records an out-of-band attention item (cleanup failures, leaked
// worktrees) without touching the job's state.
func (m *Manager) Attention(jobID int64, question string) error {
	_, err := m.AttentionID(jobID, question)
	return err
}

// AttentionID is Attention returning the escalation id (test seam).
func (m *Manager) AttentionID(jobID int64, question string) (int64, error) {
	id, err := m.Store.CreateEscalation(jobID, "attention", question, "", "", "")
	if err != nil {
		return 0, err
	}
	job, err := m.Store.GetJob(jobID)
	if err != nil {
		return 0, err
	}
	m.Notify.EscalationCreated("attention", fmt.Sprintf("agentd: %s#%d", job.Repo, job.PRNumber), question)
	if err := m.Store.TouchEscalationNotified(id); err != nil {
		return 0, err
	}
	return id, m.updateBadge()
}

func isTerminal(state string) bool {
	switch state {
	case "done", "failed", "rejected", "skipped":
		return true
	}
	return false
}

// Resolve applies a human resolution: approve executes any attached action
// (or acknowledges advice), reject requires a reason, answer requires answer
// text and resumes the consult session. Jobs already terminal only close the
// escalation.
func (m *Manager) Resolve(ctx context.Context, id int64, resolution, reason, answer string, act *actor.Actor) error {
	esc, err := m.Store.GetEscalation(id)
	if err != nil {
		return err
	}
	if esc.State != "open" {
		return fmt.Errorf("escalation %d is %s, not open", id, esc.State)
	}
	job, err := m.Store.GetJob(esc.JobID)
	if err != nil {
		return err
	}

	finish := func(state, outcome, summary string) error {
		if m.Final != nil {
			return m.Final.Finalize(ctx, esc.JobID, state, outcome, summary)
		}
		return m.Store.FinishJob(esc.JobID, state, outcome, summary)
	}

	record := func() error {
		if err := m.Store.ResolveEscalation(id, resolution, reason, answer); err != nil {
			return err
		}
		if err := m.Store.AddEvent(esc.JobID, "escalation_resolved", fmt.Sprintf(`{"resolution":%q}`, resolution)); err != nil {
			return err
		}
		return m.updateBadge()
	}

	// Finish before recording: a failed finalization leaves the escalation
	// open for retry, while the reverse could strand a resolved escalation on
	// a stuck non-terminal job.
	switch resolution {
	case "approve":
		if isTerminal(job.State) {
			return record()
		}
		if esc.ActionKind != "" {
			var params map[string]string
			if err := json.Unmarshal([]byte(esc.ActionParamsJSON), &params); err != nil {
				return err
			}
			if _, err := act.Execute(ctx, esc.JobID, policy.Action{Kind: esc.ActionKind, Params: params}, false); err != nil {
				return err
			}
			if err := finish("done", "acted", "approved by operator: "+esc.ActionKind); err != nil {
				return err
			}
			return record()
		}
		if err := finish("done", "acknowledged", "advice acknowledged by operator"); err != nil {
			return err
		}
		return record()
	case "reject":
		if reason == "" {
			return errors.New("reject requires a reason")
		}
		if !isTerminal(job.State) {
			if err := finish("rejected", "rejected", "rejected by operator: "+reason); err != nil {
				return err
			}
		}
		return record()
	case "answer":
		if answer == "" {
			return errors.New("answer requires answer text")
		}
		if m.Cont == nil {
			return errors.New("no continuation runner configured")
		}
		if err := m.Cont.Continue(ctx, esc.JobID, answer); err != nil {
			return err
		}
		return record()
	default:
		return fmt.Errorf("%q: %w", resolution, ErrUnsupportedResolution)
	}
}

// Sweep re-notifies stale open escalations and parks jobs still waiting on
// the queue. Interactive jobs and attention items re-notify but never park.
func (m *Manager) Sweep() error {
	escs, err := m.Store.OpenEscalations()
	if err != nil {
		return err
	}
	now := m.Now()
	for _, e := range escs {
		job, err := m.Store.GetJob(e.JobID)
		if err != nil {
			return err
		}
		renotify := func(title string) error {
			if m.RenotifyAfter > 0 && now.Sub(time.Unix(e.LastNotifiedTS, 0)) > m.RenotifyAfter {
				m.Notify.EscalationCreated(e.Kind, fmt.Sprintf(title, job.Repo, job.PRNumber), e.Question)
				return m.Store.TouchEscalationNotified(e.ID)
			}
			return nil
		}
		switch {
		case job.State == "parked":
			continue
		case job.State == "interactive":
			if err := renotify("agentd (drop-in still open): %s#%d"); err != nil {
				return err
			}
		case job.State == "waiting_input" || job.State == "waiting_approval":
			if m.ParkAfter > 0 && now.Sub(time.Unix(e.TS, 0)) > m.ParkAfter {
				if err := m.Store.SetJobState(e.JobID, "parked"); err != nil {
					return err
				}
				if err := m.Store.AddEvent(e.JobID, "parked", ""); err != nil {
					return err
				}
				continue
			}
			if err := renotify("agentd (still waiting): %s#%d"); err != nil {
				return err
			}
		default:
			if err := renotify("agentd (attention): %s#%d"); err != nil {
				return err
			}
		}
	}
	return m.updateBadge()
}

// RefreshBadge recomputes the badge file from open escalations.
func (m *Manager) RefreshBadge() error { return m.updateBadge() }

func (m *Manager) updateBadge() error {
	n, err := m.Store.CountOpenEscalations()
	if err != nil {
		return err
	}
	return m.Notify.SetBadge(n)
}
