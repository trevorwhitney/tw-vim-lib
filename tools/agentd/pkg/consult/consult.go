// Package consult runs advise-only opencode sessions for jobs the policy
// chain routed to a consultant, and receives their reports and questions via
// the socket API handlers.
package consult

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/tmuxctl"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/workspace"
)

// Request is what the engine hands the runner when a policy yields Consult.
// Verdicts is the policy's declared verdict->action menu; it is persisted on
// the job so reports validate identically across daemon restarts.
type Request struct {
	JobID         int64
	Repo          string
	Number        int
	Title         string
	NeedsWorktree bool
	Verdicts      map[string]policy.VerdictAction
}

type Deps struct {
	Store   *store.Store
	GH      github.Reader
	Esc     *escalate.Manager
	WS      *workspace.Manager
	Tmux    tmuxctl.Tmux
	OC      opencode.Runner
	Log     *slog.Logger
	Socket  string
	Session string // tmux session for drop-ins
	// DropinCommand is what drop-in windows run; defaults to fullscreen
	// nvim+opencode (config dropin_command).
	DropinCommand string
	// Locals maps repo (owner/name) to its local checkout. Note the key
	// difference from workspace.Manager.Sweep, which is keyed by project
	// name; GCAll remaps.
	Locals map[string]string
}

type Runner struct {
	Deps
	// base bounds every subprocess: request contexts die with their HTTP
	// response, so consults must not inherit them.
	base context.Context
	sem  chan struct{}
	wg   sync.WaitGroup
	// hbMu serializes hand-back so a manual handback and the window sweep
	// cannot both reclaim the same job.
	hbMu sync.Mutex
}

func New(base context.Context, d Deps, concurrency int) *Runner {
	if concurrency < 1 {
		concurrency = 1
	}
	return &Runner{Deps: d, base: base, sem: make(chan struct{}, concurrency)}
}

func parseJobID(tok string) (int64, error) { return strconv.ParseInt(tok, 10, 64) }

// jobEnv is the environment every consult subprocess gets: the token the
// plugin uses to self-register and call report/escalate, and the socket to
// reach.
func (r *Runner) jobEnv(jobID int64) map[string]string {
	return map[string]string{
		"AGENTD_JOB_TOKEN": strconv.FormatInt(jobID, 10),
		"AGENTD_SOCKET":    r.Socket,
		// When the daemon itself runs inside an opencode session these leak
		// into the consult subprocess, which then attaches to the parent
		// session's server and project instead of its own workspace.
		"OPENCODE":     "",
		"OPENCODE_PID": "",
	}
}

// Start runs the consult job asynchronously under the concurrency semaphore.
func (r *Runner) Start(req Request) {
	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		r.sem <- struct{}{}
		defer func() { <-r.sem }()
		r.runJob(req)
	}()
}

// Wait blocks until every in-flight consult finishes (agentd once).
func (r *Runner) Wait() { r.wg.Wait() }

// WaitTimeout blocks until every in-flight consult finishes or the timeout
// elapses; it reports whether all finished.
func (r *Runner) WaitTimeout(d time.Duration) bool {
	done := make(chan struct{})
	go func() { r.wg.Wait(); close(done) }()
	select {
	case <-done:
		return true
	case <-time.After(d):
		return false
	}
}

func (r *Runner) runJob(req Request) {
	if len(req.Verdicts) > 0 {
		b, err := json.Marshal(req.Verdicts)
		if err != nil || r.Store.SetJobVerdicts(req.JobID, string(b)) != nil {
			_ = r.Store.FailJob(req.JobID, "consult prepare: persist verdicts failed")
			return
		}
	}
	dir, err := r.prepare(req)
	if err != nil {
		r.Log.Error("consult prepare", "job", req.JobID, "err", err)
		_ = r.Store.FailJob(req.JobID, "consult prepare: "+err.Error())
		return
	}
	_ = r.Store.SetJobState(req.JobID, "running")
	_ = r.Store.AddEvent(req.JobID, "running", "")
	out, err := r.OC.Run(r.base, opencode.Request{
		Dir: dir, Env: r.jobEnv(req.JobID), Agent: "consult", Prompt: r.prompt(req),
	})
	r.afterExit(req, dir, out, err, false, "")
}

func projectName(repo string) string {
	if i := strings.LastIndexByte(repo, '/'); i >= 0 {
		return repo[i+1:]
	}
	return repo
}

func (r *Runner) prepare(req Request) (string, error) {
	pr, err := r.GH.GetPR(req.Repo, req.Number)
	if err != nil {
		return "", err
	}
	diff, err := r.GH.Diff(req.Repo, req.Number)
	if err != nil {
		return "", err
	}
	var dir string
	if req.NeedsWorktree {
		local, ok := r.Locals[req.Repo]
		if !ok || local == "" {
			return "", fmt.Errorf("repo %s needs a worktree but has no local checkout configured (repositories[].local)", req.Repo)
		}
		dir, err = r.WS.PrepareWorktree(r.base, local, projectName(req.Repo), req.JobID, req.Number)
	} else {
		dir, err = r.WS.PrepareScratch(r.base, req.JobID)
	}
	if err != nil {
		return "", err
	}
	if err := r.Store.SetJobWorktree(req.JobID, dir); err != nil {
		return "", err
	}
	art := r.WS.ArtifactDir(req.JobID)
	if err := os.MkdirAll(art, 0o755); err != nil {
		return "", err
	}
	prJSON, err := json.MarshalIndent(pr, "", "  ")
	if err != nil {
		return "", err
	}
	for name, content := range map[string][]byte{"pr.json": prJSON, "diff.patch": []byte(diff)} {
		path := filepath.Join(art, name)
		if err := os.WriteFile(path, content, 0o644); err != nil {
			return "", err
		}
		if err := r.Store.AddArtifact(req.JobID, name, path); err != nil {
			return "", err
		}
	}
	return dir, nil
}

func (r *Runner) prompt(req Request) string {
	art := r.WS.ArtifactDir(req.JobID)
	verdicts := make([]string, 0, len(req.Verdicts))
	for v := range req.Verdicts {
		verdicts = append(verdicts, v)
	}
	sort.Strings(verdicts)
	menu := "any label"
	if len(verdicts) > 0 {
		menu = "one of: " + strings.Join(verdicts, ", ")
	}
	return fmt.Sprintf(
		"You are handling agentd consult job %d: triage %s#%d — %q.\n"+
			"PR metadata: %s\nFull diff: %s\n"+
			"Follow your consult instructions: analyze the change and deliver your "+
			"recommendation with the report tool (verdict must be %s), or ask the "+
			"operator with the escalate tool. You are advise-only: never merge, "+
			"approve, comment, push, or modify anything.",
		req.JobID, req.Repo, req.Number, req.Title,
		filepath.Join(art, "pr.json"), filepath.Join(art, "diff.patch"), menu)
}

// afterExit handles a consult subprocess ending. final=false allows one
// retry; failPhase customizes the escalation wording for continuations
// (empty means the default retry phrasing).
func (r *Runner) afterExit(req Request, dir, out string, runErr error, final bool, failPhase string) {
	job, err := r.Store.GetJob(req.JobID)
	if err != nil {
		r.Log.Error("consult after exit", "job", req.JobID, "err", err)
		return
	}
	// A report or question arrived while the subprocess ran: the operator
	// owns the job now.
	if job.State == "waiting_approval" || job.State == "waiting_input" {
		return
	}
	reason := "session ended without a report or escalation"
	if runErr != nil {
		reason = runErr.Error()
	}
	if final {
		if failPhase == "" {
			failPhase = "failed after retry"
		}
		question := fmt.Sprintf("consult %s: %s — answer to nudge the session, reject to close",
			failPhase, firstLine(reason))
		if err := r.Esc.Create(req.JobID, "", question, tail(out, 2000), nil); err != nil {
			if errors.Is(err, escalate.ErrJobNotActive) {
				return
			}
			r.Log.Error("consult failure escalation", "job", req.JobID, "err", err)
		}
		return
	}
	r.Log.Warn("consult produced no result; retrying", "job", req.JobID, "reason", reason)
	retry := opencode.Request{Dir: dir, Env: r.jobEnv(req.JobID), Agent: "consult", Prompt: r.prompt(req)}
	if job.SessionID != "" {
		retry = opencode.Request{Dir: dir, Env: r.jobEnv(req.JobID), SessionID: job.SessionID,
			Prompt: "Your previous turn ended without delivering a result. Finish the consult now: " +
				"call the report tool with your recommendation, or the escalate tool with your question."}
	}
	out2, err2 := r.OC.Run(r.base, retry)
	r.afterExit(req, dir, out2, err2, true, "")
}

// RegisterSession stores the opencode session id a consult session announced.
func (r *Runner) RegisterSession(jobID int64, sessionID string) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if isTerminal(job.State) {
		return fmt.Errorf("job %d is %s; session registration rejected", jobID, job.State)
	}
	if err := r.Store.SetJobSessionID(jobID, sessionID); err != nil {
		return err
	}
	return r.Store.AddEvent(jobID, "session_registered", fmt.Sprintf(`{"session_id":%q}`, sessionID))
}

// Report records the consultant's final advice and escalates it for the
// operator's decision. The verdict must be in the job's declared set; a
// mapped action is built by the daemon from job facts and attached so that
// operator approval executes it.
func (r *Runner) Report(jobID int64, verdict, summary, details string) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if isTerminal(job.State) {
		return fmt.Errorf("job %d is %s; report rejected", jobID, job.State)
	}
	act, err := verdictAction(job, verdict, summary, details)
	if err != nil {
		return err
	}
	art := r.WS.ArtifactDir(jobID)
	if err := os.MkdirAll(art, 0o755); err != nil {
		return err
	}
	md := fmt.Sprintf("# Consult report — job %d (%s#%d)\n\n**Verdict:** %s\n\n**Summary:** %s\n\n%s\n",
		jobID, job.Repo, job.PRNumber, verdict, summary, details)
	path := filepath.Join(art, "report.md")
	if err := os.WriteFile(path, []byte(md), 0o644); err != nil {
		return err
	}
	if err := r.Store.AddArtifact(jobID, "report.md", path); err != nil {
		return err
	}
	if err := r.Store.AddEvent(jobID, "report_received", fmt.Sprintf(`{"verdict":%q}`, verdict)); err != nil {
		return err
	}
	question := fmt.Sprintf("consult verdict for %s#%d: %s — %s", job.Repo, job.PRNumber, verdict, summary)
	return r.Esc.Create(jobID, "waiting_approval", question, details, act)
}

// verdictAction validates the verdict against the job's declared menu and
// builds the mapped action. Every parameter comes from job facts; the one
// LLM-authored value is the comment body (the report itself), which executes
// only after operator approval. An empty menu (no verdicts configured)
// accepts any verdict as pure advice.
func verdictAction(job store.Job, verdict, summary, details string) (*policy.Action, error) {
	if job.VerdictsJSON == "" {
		return nil, nil
	}
	var menu map[string]policy.VerdictAction
	if err := json.Unmarshal([]byte(job.VerdictsJSON), &menu); err != nil {
		return nil, fmt.Errorf("job %d has a corrupt verdict menu: %w", job.ID, err)
	}
	va, ok := menu[verdict]
	if !ok {
		declared := make([]string, 0, len(menu))
		for v := range menu {
			declared = append(declared, v)
		}
		sort.Strings(declared)
		return nil, fmt.Errorf("verdict %q is not in the declared set %v; report again with a declared verdict", verdict, declared)
	}
	params := map[string]string{"repo": job.Repo, "number": strconv.Itoa(job.PRNumber)}
	switch va.Action {
	case "", "none":
		return nil, nil
	case "approve_pr":
		return &policy.Action{Kind: "approve_pr", Params: params}, nil
	case "merge_pr":
		params["method"] = va.Method
		if params["method"] == "" {
			params["method"] = "squash"
		}
		return &policy.Action{Kind: "merge_pr", Params: params}, nil
	case "comment_pr":
		params["body"] = fmt.Sprintf("**agentd consult** — %s\n\n%s", summary, details)
		return &policy.Action{Kind: "comment_pr", Params: params}, nil
	}
	return nil, fmt.Errorf("verdict %q maps to unknown action %q", verdict, va.Action)
}

// EscalateQuestion records a consultant question needing an operator answer.
func (r *Runner) EscalateQuestion(jobID int64, kind, question, context string) error {
	job, err := r.Store.GetJob(jobID)
	if err != nil {
		return err
	}
	if isTerminal(job.State) {
		return fmt.Errorf("job %d is %s; escalation rejected", jobID, job.State)
	}
	if err := r.Store.AddEvent(jobID, "escalated", fmt.Sprintf(`{"kind":%q}`, kind)); err != nil {
		return err
	}
	return r.Esc.Create(jobID, "waiting_input", question, context, nil)
}

func isTerminal(state string) bool {
	switch state {
	case "done", "failed", "rejected", "skipped":
		return true
	}
	return false
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

func tail(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:]
}
