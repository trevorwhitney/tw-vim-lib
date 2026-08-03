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

var ErrUnsupportedResolution = errors.New("unsupported resolution (v1 supports approve|reject)")

type Manager struct {
	Store         *store.Store
	Notify        *notify.Notifier
	RenotifyAfter time.Duration
	ParkAfter     time.Duration
	Now           func() time.Time
}

// Create records an escalation, parks the job in a waiting state, and
// notifies. act, when non-nil, is what an approval will execute.
func (m *Manager) Create(jobID int64, question, advice string, act *policy.Action) error {
	kind := "waiting_input"
	actionKind, actionParams := "", ""
	if act != nil {
		kind = "waiting_approval"
		actionKind = act.Kind
		b, err := json.Marshal(act.Params)
		if err != nil {
			return err
		}
		actionParams = string(b)
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

// Resolve applies a human resolution. approve executes any attached action
// for real; reject requires a reason and finishes the job as rejected.
func (m *Manager) Resolve(ctx context.Context, id int64, resolution, reason string, act *actor.Actor) error {
	esc, err := m.Store.GetEscalation(id)
	if err != nil {
		return err
	}
	if esc.State != "open" {
		return fmt.Errorf("escalation %d is %s, not open", id, esc.State)
	}
	switch resolution {
	case "approve":
		if esc.ActionKind == "" {
			return fmt.Errorf("escalation %d has no attached action to approve", id)
		}
		var params map[string]string
		if err := json.Unmarshal([]byte(esc.ActionParamsJSON), &params); err != nil {
			return err
		}
		if _, err := act.Execute(ctx, esc.JobID, policy.Action{Kind: esc.ActionKind, Params: params}, false); err != nil {
			return err
		}
		if err := m.Store.FinishJob(esc.JobID, "done", "acted", "approved by operator: "+esc.ActionKind); err != nil {
			return err
		}
	case "reject":
		if reason == "" {
			return errors.New("reject requires a reason")
		}
		if err := m.Store.FinishJob(esc.JobID, "rejected", "rejected", "rejected by operator: "+reason); err != nil {
			return err
		}
	default:
		return fmt.Errorf("%q: %w", resolution, ErrUnsupportedResolution)
	}
	if err := m.Store.ResolveEscalation(id, resolution, reason); err != nil {
		return err
	}
	if err := m.Store.AddEvent(esc.JobID, "escalation_resolved", fmt.Sprintf(`{"resolution":%q}`, resolution)); err != nil {
		return err
	}
	return m.updateBadge()
}

// Sweep re-notifies stale open escalations and parks jobs past ParkAfter.
// Parked escalations stay open so they remain resolvable.
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
		if job.State == "parked" {
			continue
		}
		if m.ParkAfter > 0 && now.Sub(time.Unix(e.TS, 0)) > m.ParkAfter {
			if err := m.Store.SetJobState(e.JobID, "parked"); err != nil {
				return err
			}
			if err := m.Store.AddEvent(e.JobID, "parked", ""); err != nil {
				return err
			}
			continue
		}
		if m.RenotifyAfter > 0 && now.Sub(time.Unix(e.LastNotifiedTS, 0)) > m.RenotifyAfter {
			m.Notify.EscalationCreated(e.Kind,
				fmt.Sprintf("agentd (still waiting): %s#%d", job.Repo, job.PRNumber), e.Question)
			if err := m.Store.TouchEscalationNotified(e.ID); err != nil {
				return err
			}
		}
	}
	return m.updateBadge()
}

func (m *Manager) updateBadge() error {
	n, err := m.Store.CountOpenEscalations()
	if err != nil {
		return err
	}
	return m.Notify.SetBadge(n)
}
