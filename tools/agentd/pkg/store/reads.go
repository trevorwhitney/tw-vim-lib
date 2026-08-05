package store

// InboxItem is an open escalation joined to its job.
type InboxItem struct {
	Escalation Escalation
	Job        Job
}

// escColsAliased is escCols with an e. prefix on every column. In the
// InboxItems JOIN, columns id/kind/state exist on both jobs and escalations,
// so an unqualified select would raise "ambiguous column name". Aliasing the
// whole list keeps it in lockstep with escCols/scanEscalation.
const escColsAliased = `e.id, e.job_id, e.ts, e.kind, e.question, e.advice,
	e.action_kind, e.action_params_json, e.state, e.resolution, e.reason,
	e.answer, e.last_notified_ts`

// TerminalJobs returns terminal jobs newest-first, capped at limit.
func (s *Store) TerminalJobs(limit int) ([]Job, error) {
	rows, err := s.db.Query(`SELECT `+jobCols+` FROM jobs
		WHERE state IN ('done','failed','rejected','skipped')
		ORDER BY finished_ts DESC, id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Job
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// InboxItems returns open escalations joined to their jobs, oldest first.
func (s *Store) InboxItems() ([]InboxItem, error) {
	rows, err := s.db.Query(`SELECT ` + escColsAliased + `, ` +
		"j.id, j.kind, j.repo, j.pr_number, j.head_sha, j.state, j.outcome, " +
		"j.summary, j.error, j.worktree_path, j.session_id, j.window_id, " +
		"j.verdicts_json, j.created_ts, j.updated_ts, COALESCE(j.finished_ts, 0) " +
		`FROM escalations e JOIN jobs j ON j.id = e.job_id
		 WHERE e.state='open' ORDER BY e.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []InboxItem
	for rows.Next() {
		var it InboxItem
		e := &it.Escalation
		j := &it.Job
		if err := rows.Scan(
			&e.ID, &e.JobID, &e.TS, &e.Kind, &e.Question, &e.Advice,
			&e.ActionKind, &e.ActionParamsJSON, &e.State, &e.Resolution,
			&e.Reason, &e.Answer, &e.LastNotifiedTS,
			&j.ID, &j.Kind, &j.Repo, &j.PRNumber, &j.HeadSHA, &j.State,
			&j.Outcome, &j.Summary, &j.Error, &j.WorktreePath, &j.SessionID,
			&j.WindowID, &j.VerdictsJSON, &j.CreatedTS, &j.UpdatedTS, &j.FinishedTS,
		); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// Decision is a read view of one policy-chain decision.
type Decision struct {
	ID               int64
	JobID            int64
	TS               int64
	Policy           string
	Classifier       string
	ClassifierResult string
	Verdict          string
	Rationale        string
}

func (s *Store) DecisionsForJob(jobID int64) ([]Decision, error) {
	rows, err := s.db.Query(`SELECT id, job_id, ts, policy, classifier,
		classifier_result, verdict, rationale FROM decisions WHERE job_id=? ORDER BY id`, jobID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Decision
	for rows.Next() {
		var d Decision
		if err := rows.Scan(&d.ID, &d.JobID, &d.TS, &d.Policy, &d.Classifier,
			&d.ClassifierResult, &d.Verdict, &d.Rationale); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// ActionRead is a read view of one action, including ts and executed_ts which
// the writer-side Action struct omits.
type ActionRead struct {
	ID         int64
	JobID      int64
	TS         int64
	Kind       string
	ParamsJSON string
	Simulated  bool
	ExecutedTS int64
	Result     string
	Error      string
}

func (s *Store) ActionsForJob(jobID int64) ([]ActionRead, error) {
	rows, err := s.db.Query(`SELECT id, job_id, ts, kind, params_json, simulated,
		COALESCE(executed_ts, 0), result, error FROM actions WHERE job_id=? ORDER BY id`, jobID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ActionRead
	for rows.Next() {
		var a ActionRead
		if err := rows.Scan(&a.ID, &a.JobID, &a.TS, &a.Kind, &a.ParamsJSON,
			&a.Simulated, &a.ExecutedTS, &a.Result, &a.Error); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// Event is a read view of one lifecycle event.
type Event struct {
	ID          int64
	JobID       int64
	TS          int64
	Type        string
	PayloadJSON string
}

func (s *Store) EventsForJob(jobID int64) ([]Event, error) {
	rows, err := s.db.Query(`SELECT id, job_id, ts, type, payload_json
		FROM events WHERE job_id=? ORDER BY id`, jobID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.JobID, &e.TS, &e.Type, &e.PayloadJSON); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
