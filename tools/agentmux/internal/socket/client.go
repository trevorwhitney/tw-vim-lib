// Package socket is agentmux's client for the agentd unix socket. It speaks
// HTTP+JSON over the socket (the URL host is a placeholder; routing is by
// socket path) and exchanges agentd's apitypes wire DTOs, so agentmux shares
// agentd's contract without linking its writer packages.
package socket

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

// Client dials the agentd unix socket.
type Client struct {
	hc *http.Client
}

// NewClient returns a client bound to the given unix socket path.
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

// Inbox returns open escalations joined to their jobs.
func (c *Client) Inbox() ([]apitypes.InboxItem, error) {
	var out apitypes.InboxResponse
	if err := c.do(http.MethodGet, apitypes.PathInbox, nil, &out); err != nil {
		return nil, err
	}
	return out.Items, nil
}

// Fleet returns non-terminal jobs.
func (c *Client) Fleet() ([]apitypes.Job, error) {
	var out apitypes.JobsResponse
	if err := c.do(http.MethodGet, apitypes.PathFleet, nil, &out); err != nil {
		return nil, err
	}
	return out.Jobs, nil
}

// History returns terminal jobs newest-first, capped at limit.
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

// JobDetail returns the full decision chain for one job.
func (c *Client) JobDetail(id int64) (apitypes.JobDetail, error) {
	var out apitypes.JobDetail
	return out, c.do(http.MethodGet, fmt.Sprintf("/jobs/%d?detail=1", id), nil, &out)
}

// Status fetches daemon health.
func (c *Client) Status() (apitypes.Status, error) {
	var out apitypes.Status
	return out, c.do(http.MethodGet, apitypes.PathStatus, nil, &out)
}

// Resolve resolves an escalation by its id (not the job id).
func (c *Client) Resolve(escalationID int64, resolution, reason, answer string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/escalations/%d/resolve", escalationID),
		map[string]string{"resolution": resolution, "reason": reason, "answer": answer}, nil)
}

// DropIn materializes the drop-in tmux window for a job.
func (c *Client) DropIn(jobID int64) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/dropin", jobID), struct{}{}, nil)
}

// Handback returns an interactive job to the daemon.
func (c *Client) Handback(jobID int64) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/handback", jobID), struct{}{}, nil)
}

// Retry retries a failed job.
func (c *Client) Retry(jobID int64) error {
	return c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/retry", jobID), struct{}{}, nil)
}

// SetPolling pauses or resumes the poller.
func (c *Client) SetPolling(paused bool) error {
	return c.do(http.MethodPost, "/control/polling", map[string]bool{"paused": paused}, nil)
}

// GC sweeps orphaned workspaces (job_id=0) or force-removes one job's workspace.
func (c *Client) GC(jobID int64, force bool) error {
	return c.do(http.MethodPost, "/control/gc",
		map[string]any{"job_id": jobID, "force": force}, nil)
}

// SetShadow toggles a policy's shadow flag. repo must be in owner/name form.
func (c *Client) SetShadow(repo, policy string, enabled bool) error {
	return c.do(http.MethodPost, fmt.Sprintf("/policies/%s/%s/shadow", repo, policy),
		map[string]bool{"enabled": enabled}, nil)
}
