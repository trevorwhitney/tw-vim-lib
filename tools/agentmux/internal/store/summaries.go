package store

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// LoadWorktreeSummaries reads <projectDir>/worktrees.json into a
// worktree-name → summary map. Missing/corrupt yields an empty map.
func LoadWorktreeSummaries(projectDir string) map[string]string {
	data, err := os.ReadFile(filepath.Join(projectDir, "worktrees.json"))
	if err != nil {
		return map[string]string{}
	}
	var m map[string]string
	if json.Unmarshal(data, &m) != nil {
		return map[string]string{}
	}
	return m
}
