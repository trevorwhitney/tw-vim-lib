package store

// LiveWindowSecs is the freshness window for "live". Set to >= 3x the producer
// heartbeat interval so up to two late heartbeats don't flip a running agent to
// "saved".
const LiveWindowSecs = 15

// Liveness reports "live" when the record was updated within LiveWindowSecs,
// otherwise "saved".
func Liveness(r Record, now int64) string {
	if now-r.UpdatedTS < LiveWindowSecs {
		return "live"
	}
	return "saved"
}

// AgeSecs is how long since the record was last written.
func AgeSecs(r Record, now int64) int64 {
	return now - r.UpdatedTS
}

// Validity reports "valid" when the worktree path still exists. Filesystem
// presence is canonical; workmux is advisory and not consulted here.
func Validity(path string, statPath func(string) bool) string {
	if statPath(path) {
		return "valid"
	}
	return "gone"
}

// NeedsAttention is true when the agent is waiting for the user, or when it is
// not currently live (saved/restorable, i.e. not yet brought back).
func NeedsAttention(r Record, now int64) bool {
	if r.Status == "waiting" {
		return true
	}
	return Liveness(r, now) != "live"
}
