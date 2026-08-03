package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
)

type Action struct {
	ID         int64
	JobID      int64
	Kind       string
	ParamsJSON string
	ParamsHash string
	Simulated  bool
	ExecutedTS int64
	Result     string
	Error      string
}

type Escalation struct {
	ID               int64  `json:"id"`
	JobID            int64  `json:"job_id"`
	TS               int64  `json:"ts"`
	Kind             string `json:"kind"`
	Question         string `json:"question"`
	Advice           string `json:"advice"`
	ActionKind       string `json:"action_kind"`
	ActionParamsJSON string `json:"action_params_json"`
	State            string `json:"state"`
	Resolution       string `json:"resolution"`
	Reason           string `json:"reason"`
	Answer           string `json:"answer"`
	LastNotifiedTS   int64  `json:"last_notified_ts"`
}

func (s *Store) AddDecision(jobID int64, policy, verdict, rationale string) error {
	_, err := s.db.Exec(
		`INSERT INTO decisions (job_id, ts, policy, verdict, rationale) VALUES (?, ?, ?, ?, ?)`,
		jobID, s.now().Unix(), policy, verdict, rationale)
	return err
}

// UpsertAction records intent to run an action. executed reports that this
// exact (job, kind, params) action already ran; callers must not run it again.
// A previously failed attempt is returned with executed=false so it can retry.
func (s *Store) UpsertAction(jobID int64, kind, paramsJSON string) (Action, bool, error) {
	sum := sha256.Sum256([]byte(paramsJSON))
	hash := hex.EncodeToString(sum[:])
	_, err := s.db.Exec(
		`INSERT OR IGNORE INTO actions (job_id, ts, kind, params_json, params_hash)
		 VALUES (?, ?, ?, ?, ?)`,
		jobID, s.now().Unix(), kind, paramsJSON, hash)
	if err != nil {
		return Action{}, false, err
	}
	var a Action
	var executedTS sql.NullInt64
	err = s.db.QueryRow(
		`SELECT id, job_id, kind, params_json, params_hash, simulated, executed_ts, result, error
		 FROM actions WHERE job_id=? AND kind=? AND params_hash=?`,
		jobID, kind, hash).Scan(
		&a.ID, &a.JobID, &a.Kind, &a.ParamsJSON, &a.ParamsHash, &a.Simulated, &executedTS, &a.Result, &a.Error)
	if err != nil {
		return Action{}, false, err
	}
	a.ExecutedTS = executedTS.Int64
	return a, executedTS.Valid, nil
}

// MarkActionExecuted records completion. simulated distinguishes recorded-only
// completions (shadow / dry-run, named in result) from real executions.
func (s *Store) MarkActionExecuted(id int64, result string, simulated bool) error {
	_, err := s.db.Exec(
		`UPDATE actions SET executed_ts=?, result=?, simulated=?, error='' WHERE id=?`,
		s.now().Unix(), result, simulated, id)
	return err
}

func (s *Store) MarkActionFailed(id int64, errMsg string) error {
	_, err := s.db.Exec(`UPDATE actions SET error=? WHERE id=?`, errMsg, id)
	return err
}

const escCols = `id, job_id, ts, kind, question, advice, action_kind, action_params_json,
	state, resolution, reason, answer, last_notified_ts`

func scanEscalation(row interface{ Scan(...any) error }) (Escalation, error) {
	var e Escalation
	err := row.Scan(&e.ID, &e.JobID, &e.TS, &e.Kind, &e.Question, &e.Advice,
		&e.ActionKind, &e.ActionParamsJSON, &e.State, &e.Resolution, &e.Reason, &e.Answer, &e.LastNotifiedTS)
	return e, err
}

func (s *Store) CreateEscalation(jobID int64, kind, question, advice, actionKind, actionParamsJSON string) (int64, error) {
	res, err := s.db.Exec(
		`INSERT INTO escalations (job_id, ts, kind, question, advice, action_kind, action_params_json)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		jobID, s.now().Unix(), kind, question, advice, actionKind, actionParamsJSON)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) GetEscalation(id int64) (Escalation, error) {
	return scanEscalation(s.db.QueryRow(`SELECT `+escCols+` FROM escalations WHERE id=?`, id))
}

func (s *Store) OpenEscalations() ([]Escalation, error) {
	rows, err := s.db.Query(`SELECT ` + escCols + ` FROM escalations WHERE state='open' ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Escalation
	for rows.Next() {
		e, err := scanEscalation(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) OpenEscalationForJob(jobID int64) (Escalation, bool, error) {
	e, err := scanEscalation(s.db.QueryRow(
		`SELECT `+escCols+` FROM escalations WHERE job_id=? AND state='open'`, jobID))
	if errors.Is(err, sql.ErrNoRows) {
		return Escalation{}, false, nil
	}
	return e, err == nil, err
}

func (s *Store) CountOpenEscalations() (int, error) {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM escalations WHERE state='open'`).Scan(&n)
	return n, err
}

func (s *Store) ResolveEscalation(id int64, resolution, reason, answer string) error {
	_, err := s.db.Exec(
		`UPDATE escalations SET state='resolved', resolution=?, reason=?, answer=?, resolved_ts=? WHERE id=? AND state='open'`,
		resolution, reason, answer, s.now().Unix(), id)
	return err
}

func (s *Store) TouchEscalationNotified(id int64) error {
	_, err := s.db.Exec(`UPDATE escalations SET last_notified_ts=? WHERE id=?`, s.now().Unix(), id)
	return err
}

type Artifact struct {
	ID    int64  `json:"id"`
	JobID int64  `json:"job_id"`
	Name  string `json:"name"`
	Path  string `json:"path"`
}

func (s *Store) AddArtifact(jobID int64, name, path string) error {
	_, err := s.db.Exec(`INSERT INTO artifacts (job_id, name, path) VALUES (?, ?, ?)`, jobID, name, path)
	return err
}

func (s *Store) ArtifactsForJob(jobID int64) ([]Artifact, error) {
	rows, err := s.db.Query(`SELECT id, job_id, name, path FROM artifacts WHERE job_id=? ORDER BY id`, jobID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Artifact
	for rows.Next() {
		var a Artifact
		if err := rows.Scan(&a.ID, &a.JobID, &a.Name, &a.Path); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}
