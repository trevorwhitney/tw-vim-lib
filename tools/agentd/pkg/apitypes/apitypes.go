// Package apitypes is the dependency-free wire contract between agentd and its
// socket clients (agentmux, the CLI). It contains only DTOs and imports
// nothing from agentd's internals, so a client can depend on the
// request/response shapes without linking the daemon's store or engine
// packages. JSON field names are the contract and must stay stable.
package apitypes

// Job is a ledger job as seen on the wire.
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

// Escalation is an open or resolved attention item on the wire.
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

// RepoStatus is a repo's poller state.
type RepoStatus struct {
	Repo       string `json:"repo"`
	LastPollTS int64  `json:"last_poll_ts"`
	LastError  string `json:"last_error"`
	AuthError  bool   `json:"auth_error"`
}

// Status is the GET /status response.
type Status struct {
	Paused          bool         `json:"paused"`
	OpenEscalations int          `json:"open_escalations"`
	Repos           []RepoStatus `json:"repos"`
}

// JobResponse is the GET /jobs/{id} response (job plus its open escalation).
type JobResponse struct {
	Job        Job         `json:"job"`
	Escalation *Escalation `json:"escalation,omitempty"`
}
