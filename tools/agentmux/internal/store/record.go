package store

import "encoding/json"

// Record is one agent's persisted state from the global mirror. It mirrors the
// JSON written by the nvim plugin's global.lua.
type Record struct {
	Project     string `json:"project"`
	Worktree    string `json:"worktree"`
	Path        string `json:"path"`
	Handle      string `json:"handle"`
	Mode        string `json:"mode"`
	Idx         int    `json:"idx"`
	Status      string `json:"status"`
	Description string `json:"description"`
	SessionID   string `json:"session_id"`
	UpdatedTS   int64  `json:"updated_ts"`
	Schema      int    `json:"schema"`
}

// ParseRecord decodes a single mirror record file's contents.
func ParseRecord(data []byte) (Record, error) {
	var r Record
	if err := json.Unmarshal(data, &r); err != nil {
		return Record{}, err
	}
	return r, nil
}
