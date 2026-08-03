package store

import (
	"database/sql"
	"errors"
)

type Job struct {
	ID         int64  `json:"id"`
	Kind       string `json:"kind"`
	Repo       string `json:"repo"`
	PRNumber   int    `json:"pr_number"`
	HeadSHA    string `json:"head_sha"`
	State      string `json:"state"`
	Outcome    string `json:"outcome"`
	Summary    string `json:"summary"`
	Error      string `json:"error"`
	CreatedTS  int64  `json:"created_ts"`
	UpdatedTS  int64  `json:"updated_ts"`
	FinishedTS int64  `json:"finished_ts"`
}

const jobCols = "id, kind, repo, pr_number, head_sha, state, outcome, summary, error, created_ts, updated_ts, COALESCE(finished_ts, 0)"

func scanJob(row interface{ Scan(...any) error }) (Job, error) {
	var j Job
	err := row.Scan(&j.ID, &j.Kind, &j.Repo, &j.PRNumber, &j.HeadSHA, &j.State,
		&j.Outcome, &j.Summary, &j.Error, &j.CreatedTS, &j.UpdatedTS, &j.FinishedTS)
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

func (s *Store) AddEvent(jobID int64, typ, payloadJSON string) error {
	_, err := s.db.Exec(`INSERT INTO events (job_id, ts, type, payload_json) VALUES (?, ?, ?, ?)`,
		jobID, s.now().Unix(), typ, payloadJSON)
	return err
}
