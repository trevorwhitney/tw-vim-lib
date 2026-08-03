package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
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

func (c *Client) Status() (StatusResponse, error) {
	var out StatusResponse
	return out, c.do(http.MethodGet, "/status", nil, &out)
}

func (c *Client) Enqueue(repo string, prNumber int) (store.Job, error) {
	var out store.Job
	return out, c.do(http.MethodPost, "/jobs",
		map[string]any{"repo": repo, "pr_number": prNumber}, &out)
}

func (c *Client) Job(id int64) (JobResponse, error) {
	var out JobResponse
	return out, c.do(http.MethodGet, fmt.Sprintf("/jobs/%d", id), nil, &out)
}

func (c *Client) Retry(id int64) (store.Job, error) {
	var out store.Job
	return out, c.do(http.MethodPost, fmt.Sprintf("/jobs/%d/retry", id), nil, &out)
}

func (c *Client) Resolve(escalationID int64, resolution, reason, answer string) error {
	return c.do(http.MethodPost, fmt.Sprintf("/escalations/%d/resolve", escalationID),
		map[string]string{"resolution": resolution, "reason": reason, "answer": answer}, nil)
}

func (c *Client) SetPolling(paused bool) error {
	return c.do(http.MethodPost, "/control/polling", map[string]bool{"paused": paused}, nil)
}
