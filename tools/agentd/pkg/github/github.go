// Package github defines agentd's GitHub contract — the Reader/Writer
// interfaces and their typed request/response shapes — plus the gh-CLI
// implementation in client.go.
package github

import "context"

type PR struct {
	Number  int
	Title   string
	Body    string
	URL     string
	Draft   bool
	HeadSHA string
	BaseRef string
	Author  string
}

type CIState string

const (
	CISuccess CIState = "success"
	CIPending CIState = "pending"
	CIFailure CIState = "failure"
)

type Mergeability string

const (
	MergeClean   Mergeability = "clean"
	MergeDirty   Mergeability = "dirty"
	MergeUnknown Mergeability = "unknown"
)

// Facts is the per-PR state the universal checks and policies consume.
type Facts struct {
	CI        CIState
	Mergeable Mergeability
}

// Reader is the read surface the engine polls with.
type Reader interface {
	ListOpenPRs(repo string) ([]PR, error)
	GetPR(repo string, number int) (PR, error)
	// ChangedFiles reports every changed file path; truncated is true when
	// GitHub's listing cap may have cut the list short.
	ChangedFiles(repo string, number int) (files []string, truncated bool, err error)
	Facts(repo string, number int) (Facts, error)
	// Diff returns the PR's full unified diff.
	Diff(repo string, number int) (string, error)
	// Viewer returns the authenticated user's login.
	Viewer() (string, error)
}

// Writer is the write surface the actor executes through.
type Writer interface {
	MergePR(ctx context.Context, repo string, number int, method string) (string, error)
	// EnableAutoMerge queues the merge for when the branch's own requirements
	// are met, leaving GitHub to enforce checks rather than the daemon.
	EnableAutoMerge(ctx context.Context, repo string, number int, method string) (string, error)
	ApprovePR(ctx context.Context, repo string, number int) (string, error)
	CommentPR(ctx context.Context, repo string, number int, body string) (string, error)
}

type Interface interface {
	Reader
	Writer
}

// AuthError marks credential failures, which callers must not retry.
type AuthError struct{ Msg string }

func (e *AuthError) Error() string { return "github auth error: " + e.Msg }
