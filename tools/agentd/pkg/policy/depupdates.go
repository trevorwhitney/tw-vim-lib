package policy

import (
	"fmt"
	"slices"
	"strconv"
	"strings"

	"github.com/bmatcuk/doublestar/v4"
	"gopkg.in/yaml.v3"
)

// DepUpdates approves dependency-bot PRs whose changed files all match the
// allowed path globs and hands the merge to GitHub's auto-merge; anything else
// it escalates with that same action attached.
type DepUpdates struct {
	AllowedPaths   []string `yaml:"allowed_paths"`
	AllowedAuthors []string `yaml:"allowed_authors"`
	MergeMethod    string   `yaml:"merge_method"`
}

var depBots = []string{"renovate[bot]", "dependabot[bot]"}

func NewDepUpdates(raw *yaml.Node) (*DepUpdates, error) {
	p := &DepUpdates{
		AllowedPaths: []string{"go.mod", "go.sum", "vendor/**"},
		MergeMethod:  "squash",
	}
	if raw != nil {
		if err := raw.Decode(p); err != nil {
			return nil, err
		}
	}
	switch p.MergeMethod {
	case "squash", "merge", "rebase":
	default:
		return nil, fmt.Errorf("merge_method must be squash|merge|rebase, got %q", p.MergeMethod)
	}
	for _, pattern := range p.AllowedPaths {
		if !doublestar.ValidatePattern(pattern) {
			return nil, fmt.Errorf("invalid allowed_paths pattern %q", pattern)
		}
	}
	return p, nil
}

func (p *DepUpdates) Name() string { return "merge-dependency-updates" }

func (p *DepUpdates) Evaluate(in Input) (Result, error) {
	author := in.Facts.PR.Author
	if !slices.Contains(depBots, author) && !slices.Contains(p.AllowedAuthors, author) {
		return Result{Verdict: Pass, Rationale: fmt.Sprintf("author %q is not a dependency bot", author)}, nil
	}

	action := &Action{
		Kind: "approve_and_automerge",
		Params: map[string]string{
			"repo":   in.Repo,
			"number": strconv.Itoa(in.Facts.PR.Number),
			"method": p.MergeMethod,
		},
	}

	if in.FilesTruncated {
		return Result{
			Verdict:   Escalate,
			Question:  "dependency PR has too many changed files to verify against allowed paths",
			Rationale: "changed-file list truncated",
			Action:    action,
		}, nil
	}

	var outside []string
	for _, f := range in.Files {
		if !p.matches(f) {
			outside = append(outside, f)
		}
	}
	if len(outside) > 0 {
		return Result{
			Verdict:   Escalate,
			Question:  fmt.Sprintf("dependency PR touches files outside allowed paths: %s", strings.Join(outside, ", ")),
			Rationale: fmt.Sprintf("%d file(s) outside allowed paths", len(outside)),
			Action:    action,
		}, nil
	}
	return Result{
		Verdict:   Act,
		Rationale: fmt.Sprintf("all %d changed files match allowed paths", len(in.Files)),
		Action:    action,
	}, nil
}

func (p *DepUpdates) matches(file string) bool {
	for _, pattern := range p.AllowedPaths {
		if ok, err := doublestar.Match(pattern, file); err == nil && ok {
			return true
		}
	}
	return false
}
