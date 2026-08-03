-- +goose Up
CREATE TABLE jobs (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,
  repo TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  state TEXT NOT NULL,
  outcome TEXT NOT NULL DEFAULT '',
  worktree_path TEXT NOT NULL DEFAULT '',
  session_id TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT '',
  created_ts INTEGER NOT NULL,
  updated_ts INTEGER NOT NULL,
  finished_ts INTEGER,
  UNIQUE (repo, pr_number, head_sha, kind)
);
CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  ts INTEGER NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT ''
);
CREATE TABLE decisions (
  id INTEGER PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  ts INTEGER NOT NULL,
  policy TEXT NOT NULL,
  classifier TEXT NOT NULL DEFAULT '',
  classifier_result TEXT NOT NULL DEFAULT '',
  verdict TEXT NOT NULL,
  rationale TEXT NOT NULL DEFAULT ''
);
CREATE TABLE actions (
  id INTEGER PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  ts INTEGER NOT NULL,
  kind TEXT NOT NULL,
  params_json TEXT NOT NULL,
  params_hash TEXT NOT NULL,
  simulated INTEGER NOT NULL DEFAULT 0,
  executed_ts INTEGER,
  result TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT '',
  UNIQUE (job_id, kind, params_hash)
);
CREATE TABLE escalations (
  id INTEGER PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  ts INTEGER NOT NULL,
  kind TEXT NOT NULL,
  question TEXT NOT NULL,
  advice TEXT NOT NULL DEFAULT '',
  action_kind TEXT NOT NULL DEFAULT '',
  action_params_json TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'open',
  resolution TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT '',
  resolved_ts INTEGER,
  last_notified_ts INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE artifacts (
  id INTEGER PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  name TEXT NOT NULL,
  path TEXT NOT NULL
);

-- +goose Down
DROP TABLE artifacts;
DROP TABLE escalations;
DROP TABLE actions;
DROP TABLE decisions;
DROP TABLE events;
DROP TABLE jobs;
