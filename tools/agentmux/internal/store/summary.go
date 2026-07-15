package store

// Summary resolves a never-blank worktree label: the worktrees.json summary if
// present, else the git branch (via branchOf, which may be nil / return ""),
// else the worktree name.
func Summary(r Record, wtSummaries map[string]string, branchOf func(Record) string) string {
	if wtSummaries != nil {
		if s := wtSummaries[r.Worktree]; s != "" {
			return s
		}
	}
	if branchOf != nil {
		if b := branchOf(r); b != "" {
			return b
		}
	}
	return r.Worktree
}
