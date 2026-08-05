package github

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
)

// Client implements Reader and Writer by shelling out to the gh CLI, which
// owns auth, token refresh, and host config.
type Client struct {
	exec execx.Execer

	mu    sync.Mutex
	login string
}

var _ Interface = (*Client)(nil)

func New(exec execx.Execer) *Client { return &Client{exec: exec} }

// classify types auth failures so callers can stop polling a repo instead of
// retrying a credential problem.
func classify(err error) error {
	if err == nil {
		return nil
	}
	msg := err.Error()
	if strings.Contains(msg, "HTTP 401") || strings.Contains(msg, "HTTP 403") ||
		strings.Contains(msg, "gh auth login") {
		return &AuthError{Msg: msg}
	}
	return err
}

func (c *Client) gh(ctx context.Context, args ...string) (string, error) {
	out, err := c.exec(ctx, "gh", args...)
	if err != nil {
		return "", classify(err)
	}
	return out, nil
}

type rawPR struct {
	Number      int    `json:"number"`
	Title       string `json:"title"`
	Body        string `json:"body"`
	URL         string `json:"url"`
	IsDraft     bool   `json:"isDraft"`
	HeadRefOid  string `json:"headRefOid"`
	BaseRefName string `json:"baseRefName"`
	Author      struct {
		Login string `json:"login"`
	} `json:"author"`
}

func (r rawPR) pr() PR {
	return PR{Number: r.Number, Title: r.Title, Body: r.Body, URL: r.URL, Draft: r.IsDraft,
		HeadSHA: r.HeadRefOid, BaseRef: r.BaseRefName, Author: r.Author.Login}
}

const prJSONFields = "number,title,body,url,isDraft,headRefOid,baseRefName,author"

func (c *Client) ListOpenPRs(repo string) ([]PR, error) {
	out, err := c.gh(context.Background(), "pr", "list", "--repo", repo, "--state", "open",
		"--limit", "200", "--json", prJSONFields)
	if err != nil {
		return nil, err
	}
	var raw []rawPR
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return nil, err
	}
	prs := make([]PR, 0, len(raw))
	for _, r := range raw {
		prs = append(prs, r.pr())
	}
	return prs, nil
}

func (c *Client) Viewer() (string, error) {
	c.mu.Lock()
	login := c.login
	c.mu.Unlock()
	if login != "" {
		return login, nil
	}
	out, err := c.gh(context.Background(), "api", "user", "--jq", ".login")
	if err != nil {
		return "", err
	}
	login = strings.TrimSpace(out)
	c.mu.Lock()
	c.login = login
	c.mu.Unlock()
	return login, nil
}

func (c *Client) MergePR(ctx context.Context, repo string, number int, method string) (string, error) {
	return c.gh(ctx, "pr", "merge", strconv.Itoa(number), "--repo", repo, "--"+method)
}

func (c *Client) ApprovePR(ctx context.Context, repo string, number int) (string, error) {
	return c.gh(ctx, "pr", "review", strconv.Itoa(number), "--repo", repo, "--approve")
}

func (c *Client) CommentPR(ctx context.Context, repo string, number int, body string) (string, error) {
	return c.gh(ctx, "pr", "comment", strconv.Itoa(number), "--repo", repo, "--body", body)
}

func (c *Client) GetPR(repo string, number int) (PR, error) {
	out, err := c.gh(context.Background(), "pr", "view", strconv.Itoa(number), "--repo", repo,
		"--json", prJSONFields)
	if err != nil {
		return PR{}, err
	}
	var raw rawPR
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return PR{}, err
	}
	return raw.pr(), nil
}

type statusCheck struct {
	Typename   string `json:"__typename"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	State      string `json:"state"`
}

// Facts reports mergeability and CI state for one PR. CI reflects the repo's
// required checks when it defines any; otherwise every check counts.
func (c *Client) Facts(repo string, number int) (Facts, error) {
	out, err := c.gh(context.Background(), "pr", "view", strconv.Itoa(number), "--repo", repo,
		"--json", "mergeable,statusCheckRollup")
	if err != nil {
		return Facts{}, err
	}
	var raw struct {
		Mergeable         string        `json:"mergeable"`
		StatusCheckRollup []statusCheck `json:"statusCheckRollup"`
	}
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return Facts{}, err
	}

	facts := Facts{CI: CISuccess}
	switch raw.Mergeable {
	case "MERGEABLE":
		facts.Mergeable = MergeClean
	case "CONFLICTING":
		facts.Mergeable = MergeDirty
	default:
		facts.Mergeable = MergeUnknown
	}

	requiredCI, ok, err := c.requiredCI(repo, number)
	// Ignore errors about no required or no checks - fall back to all checks
	ignoreErr := err != nil && (strings.Contains(err.Error(), "no required checks") ||
		strings.Contains(err.Error(), "no checks reported"))
	if err != nil && !ignoreErr {
		return Facts{}, err
	}
	if ok {
		facts.CI = requiredCI
	} else {
		facts.CI = allChecksCI(raw.StatusCheckRollup)
	}

	return facts, nil
}

// Failure always wins; pending survives later successes.
func allChecksCI(rollup []statusCheck) CIState {
	result := CISuccess
	for _, s := range rollup {
		verdict := s.Conclusion
		if s.Typename == "StatusContext" {
			verdict = s.State
		}
		switch verdict {
		case "FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED":
			return CIFailure
		case "SUCCESS", "NEUTRAL", "SKIPPED":
		default:
			result = CIPending
		}
	}
	return result
}

func (c *Client) requiredCI(repo string, number int) (CIState, bool, error) {
	out, err := c.gh(context.Background(), "pr", "checks", strconv.Itoa(number), "--repo", repo,
		"--required", "--json", "bucket")
	if err != nil {
		return "", false, err
	}

	var checks []struct {
		Bucket string `json:"bucket"`
	}
	if err := json.Unmarshal([]byte(out), &checks); err != nil {
		return "", false, err
	}

	if len(checks) == 0 {
		return "", false, nil
	}

	result := CISuccess
	for _, check := range checks {
		switch check.Bucket {
		case "fail", "cancel":
			return CIFailure, true, nil
		case "pass", "skipping":
		default:
			// Unknown buckets count as pending: never merge on a verdict we
			// don't understand.
			result = CIPending
		}
	}
	return result, true, nil
}

// fileListCap is GitHub's hard limit on the PR files listing; at the cap the
// list may be incomplete.
const fileListCap = 3000

func (c *Client) ChangedFiles(repo string, number int) ([]string, bool, error) {
	out, err := c.gh(context.Background(), "api", "--paginate",
		fmt.Sprintf("repos/%s/pulls/%d/files", repo, number), "--jq", ".[].filename")
	if err != nil {
		return nil, false, err
	}
	var files []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line != "" {
			files = append(files, line)
		}
	}
	return files, len(files) >= fileListCap, nil
}

func (c *Client) Diff(repo string, number int) (string, error) {
	return c.gh(context.Background(), "pr", "diff", strconv.Itoa(number), "--repo", repo)
}
