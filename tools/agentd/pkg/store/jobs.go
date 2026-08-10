package store

import (
	"database/sql"
	"errors"
	"strings"
)

type Job struct {
	ID           int64  `json:"id"`
	Kind         string `json:"kind"`
	Repo         string `json:"repo"`
	PRNumber     int    `json:"pr_number"`
	HeadSHA      string `json:"head_sha"`
	State        string `json:"state"`
	Outcome      string `json:"outcome"`
	Summary      string `json:"summary"`
	Error        string `json:"error"`
	WorktreePath string `json:"worktree_path"`
	SessionID    string `json:"session_id"`
	WindowID     string `json:"window_id"`
	VerdictsJSON string `json:"verdicts_json"`
	CreatedTS    int64  `json:"created_ts"`
	UpdatedTS    int64  `json:"updated_ts"`
	FinishedTS   int64  `json:"finished_ts"`
}

const jobCols = "id, kind, repo, pr_number, head_sha, state, outcome, summary, error, worktree_path, session_id, window_id, verdicts_json, created_ts, updated_ts, COALESCE(finished_ts, 0)"

func scanJob(row interface{ Scan(...any) error }) (Job, error) {
	var j Job
	err := row.Scan(&j.ID, &j.Kind, &j.Repo, &j.PRNumber, &j.HeadSHA, &j.State,
		&j.Outcome, &j.Summary, &j.Error, &j.WorktreePath, &j.SessionID, &j.WindowID,
		&j.VerdictsJSON, &j.CreatedTS, &j.UpdatedTS, &j.FinishedTS)
	return j, err
}

// CreateJob inserts a queued job. The (repo, pr_number, head_sha, kind) key is
// unique; inserting a duplicate returns an error.
func (s *Store) CreateJob(kind, repo string, prNumber int, headSHA string) (int64, error) {
	ts := s.now().Unix()
	res, err := s.db.Exec(
		`INSERT INTO jobs (kind, repo, pr_number, head_sha, state, created_ts, updated_ts)
		 VALUES (?, ?, ?, ?, 'queued', ?, ?)`,
		kind, repo, prNumber, headSHA, ts, ts)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) HasJob(repo string, prNumber int, headSHA, kind string) (bool, error) {
	var one int
	err := s.db.QueryRow(
		`SELECT 1 FROM jobs WHERE repo=? AND pr_number=? AND head_sha=? AND kind=?`,
		repo, prNumber, headSHA, kind).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (s *Store) GetJob(id int64) (Job, error) {
	return scanJob(s.db.QueryRow(`SELECT `+jobCols+` FROM jobs WHERE id=?`, id))
}

func (s *Store) JobForHead(repo string, prNumber int, headSHA, kind string) (Job, bool, error) {
	j, err := scanJob(s.db.QueryRow(
		`SELECT `+jobCols+` FROM jobs WHERE repo=? AND pr_number=? AND head_sha=? AND kind=?`,
		repo, prNumber, headSHA, kind))
	if errors.Is(err, sql.ErrNoRows) {
		return Job{}, false, nil
	}
	return j, err == nil, err
}

func (s *Store) SetJobState(id int64, state string) error {
	_, err := s.db.Exec(`UPDATE jobs SET state=?, updated_ts=? WHERE id=?`, state, s.now().Unix(), id)
	return err
}

// ClaimJobState atomically moves the job to state to, but only if its current
// state is one of from. It reports whether the claim won; a lost claim means
// another writer moved the job first.
func (s *Store) ClaimJobState(id int64, to string, from ...string) (bool, error) {
	if len(from) == 0 {
		return false, errors.New("ClaimJobState requires at least one from state")
	}
	q := `UPDATE jobs SET state=?, updated_ts=? WHERE id=? AND state IN (?` +
		strings.Repeat(",?", len(from)-1) + `)`
	args := []any{to, s.now().Unix(), id}
	for _, f := range from {
		args = append(args, f)
	}
	res, err := s.db.Exec(q, args...)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n > 0, err
}

// FinishJob moves a job to a terminal state with its outcome and summary.
func (s *Store) FinishJob(id int64, state, outcome, summary string) error {
	ts := s.now().Unix()
	_, err := s.db.Exec(
		`UPDATE jobs SET state=?, outcome=?, summary=?, updated_ts=?, finished_ts=? WHERE id=?`,
		state, outcome, summary, ts, ts, id)
	return err
}

func (s *Store) FailJob(id int64, errMsg string) error {
	ts := s.now().Unix()
	_, err := s.db.Exec(
		`UPDATE jobs SET state='failed', outcome='failed', error=?, updated_ts=?, finished_ts=? WHERE id=?`,
		errMsg, ts, ts, id)
	return err
}

// ResetJob returns a job to queued so it can be re-evaluated (retry path).
func (s *Store) ResetJob(id int64) error {
	_, err := s.db.Exec(
		`UPDATE jobs SET state='queued', outcome='', error='', summary='', updated_ts=?, finished_ts=NULL WHERE id=?`,
		s.now().Unix(), id)
	return err
}

func (s *Store) JobsInState(state string) ([]Job, error) {
	rows, err := s.db.Query(`SELECT `+jobCols+` FROM jobs WHERE state=? ORDER BY id`, state)
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

func (s *Store) SetJobSessionID(id int64, sessionID string) error {
	_, err := s.db.Exec(`UPDATE jobs SET session_id=?, updated_ts=? WHERE id=?`, sessionID, s.now().Unix(), id)
	return err
}

func (s *Store) SetJobWorktree(id int64, path string) error {
	_, err := s.db.Exec(`UPDATE jobs SET worktree_path=?, updated_ts=? WHERE id=?`, path, s.now().Unix(), id)
	return err
}

func (s *Store) SetJobWindowID(id int64, windowID string) error {
	_, err := s.db.Exec(`UPDATE jobs SET window_id=?, updated_ts=? WHERE id=?`, windowID, s.now().Unix(), id)
	return err
}

func (s *Store) SetJobVerdicts(id int64, verdictsJSON string) error {
	_, err := s.db.Exec(`UPDATE jobs SET verdicts_json=?, updated_ts=? WHERE id=?`, verdictsJSON, s.now().Unix(), id)
	return err
}

// NonTerminalJobs returns every job not yet in a terminal state (done,
// failed, rejected, skipped). Parked and waiting jobs are non-terminal.
func (s *Store) NonTerminalJobs() ([]Job, error) {
	rows, err := s.db.Query(`SELECT ` + jobCols + ` FROM jobs
		WHERE state NOT IN ('done', 'failed', 'rejected', 'skipped') ORDER BY id`)
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

func (s *Store) HasEvent(jobID int64, typ string) (bool, error) {
	var one int
	err := s.db.QueryRow(`SELECT 1 FROM events WHERE job_id=? AND type=? LIMIT 1`, jobID, typ).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// LatestEventPayload returns the payload of the most recent event of the
// given type, with ok=false when none exists.
func (s *Store) LatestEventPayload(jobID int64, typ string) (string, bool, error) {
	var payload string
	err := s.db.QueryRow(
		`SELECT payload_json FROM events WHERE job_id=? AND type=? ORDER BY id DESC LIMIT 1`,
		jobID, typ).Scan(&payload)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return payload, err == nil, err
}

func (s *Store) AddEvent(jobID int64, typ, payloadJSON string) error {
	_, err := s.db.Exec(`INSERT INTO events (job_id, ts, type, payload_json) VALUES (?, ?, ?, ?)`,
		jobID, s.now().Unix(), typ, payloadJSON)
	return err
}
