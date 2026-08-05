package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

type Client struct {
	hc *http.Client
}

// NewClient returns a client that dials the agentd unix socket. The http URL
// host is a placeholder; routing happens over the socket.
func NewClient(socketPath string) *Client {
	return &Client{hc: &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, "unix", socketPath)
			},
		},
	}}
}

func (c *Client) do(method, path string, body, out any) error {
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, "http://agentd"+path, rdr)
	if err != nil {
		return err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return fmt.Errorf("is agentd running? %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		var e struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&e)
		return fmt.Errorf("%s %s: %s: %s", method, path, resp.Status, e.Error)
	}
	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}

func (c *Client) Status() (apitypes.Status, error) {
	var out apitypes.Status
	return out, c.do(http.MethodGet, apitypes.PathStatus, nil, &out)
}

func (c *Client) Enqueue(repo string, prNumber int) (apitypes.Job, error) {
	var out apitypes.Job
	return out, c.do(http.MethodPost, "/jobs",
		map[string]any{"repo": repo, "pr_number": prNumber}, &out)
}

func (c *Client) Job(id int64) (apitypes.JobResponse, error) {
	var out apitypes.JobResponse
	return out, c.do(http.MethodGet, fmt.Sprintf("/jobs/%d", id), nil, &out)
}

func (c *Client) Retry(id int64) (apitypes.Job, error) {
	var out apitypes.Job
	return out, c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/retry", id), nil, &out)
}

func (c *Client) Resolve(escalationID int64, resolution, reason, answer string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/escalations/%d/resolve", escalationID),
		map[string]string{"resolution": resolution, "reason": reason, "answer": answer}, nil)
}

func (c *Client) SetPolling(paused bool) error {
	return c.do(http.MethodPost, "/control/polling", map[string]bool{"paused": paused}, nil)
}

func (c *Client) RegisterSession(jobID int64, sessionID string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/session", jobID),
		map[string]string{"session_id": sessionID}, nil)
}

func (c *Client) Report(jobID int64, verdict, summary, details string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/report", jobID),
		map[string]string{"verdict": verdict, "summary": summary, "details": details}, nil)
}

func (c *Client) EscalateJob(jobID int64, kind, question, context string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/escalate", jobID),
		map[string]string{"kind": kind, "question": question, "context": context}, nil)
}

func (c *Client) DropIn(jobID int64) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/dropin", jobID), struct{}{}, nil)
}

func (c *Client) Handback(jobID int64) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/handback", jobID), struct{}{}, nil)
}

func (c *Client) GC(jobID int64, force bool) error {
	return c.do(http.MethodPost, "/control/gc",
		map[string]any{"job_id": jobID, "force": force}, nil)
}

// SetShadow toggles a policy's shadow flag. repo must be exactly owner/name.
func (c *Client) SetShadow(repo, policy string, enabled bool) error {
	return c.do(http.MethodPost, fmt.Sprintf("/policies/%s/%s/shadow", repo, policy),
		map[string]bool{"enabled": enabled}, nil)
}

func (c *Client) Inbox() ([]apitypes.InboxItem, error) {
	var out apitypes.InboxResponse
	if err := c.do(http.MethodGet, apitypes.PathInbox, nil, &out); err != nil {
		return nil, err
	}
	return out.Items, nil
}

func (c *Client) Fleet() ([]apitypes.Job, error) {
	var out apitypes.JobsResponse
	if err := c.do(http.MethodGet, apitypes.PathFleet, nil, &out); err != nil {
		return nil, err
	}
	return out.Jobs, nil
}

func (c *Client) JobDetail(id int64) (apitypes.JobDetail, error) {
	var out apitypes.JobDetail
	return out, c.do(http.MethodGet, fmt.Sprintf("/jobs/%d?detail=1", id), nil, &out)
}

func (c *Client) History(limit int) ([]apitypes.Job, error) {
	var out apitypes.JobsResponse
	path := apitypes.PathHistory
	if limit > 0 {
		path += "?limit=" + strconv.Itoa(limit)
	}
	if err := c.do(http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}
	return out.Jobs, nil
}
