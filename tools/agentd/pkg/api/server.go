// Package api serves the agentd control surface over a unix socket and
// provides the matching client used by CLI subcommands.
package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/consult"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

type Server struct {
	Engine  *engine.Engine
	Esc     *escalate.Manager
	Actor   *actor.Actor
	Store   *store.Store
	Consult *consult.Runner
}

// Aliases keep existing api.StatusResponse/api.JobResponse references working
// while apitypes owns the canonical wire definitions.
type StatusResponse = apitypes.Status
type JobResponse = apitypes.JobResponse

// Listen binds the unix socket at path with 0600 permissions, replacing any
// stale socket file.
func Listen(path string) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	_ = os.Remove(path)
	ln, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		_ = ln.Close()
		return nil, err
	}
	return ln, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /status", s.status)
	mux.HandleFunc("GET /inbox", s.inbox)
	mux.HandleFunc("GET /fleet", s.fleet)
	mux.HandleFunc("GET /history", s.history)
	mux.HandleFunc("POST /jobs", s.enqueue)
	mux.HandleFunc("GET /jobs/{id}", s.getJob)
	mux.HandleFunc("POST /jobs/{id}/retry", s.retry)
	mux.HandleFunc("POST /escalations/{id}/resolve", s.resolve)
	mux.HandleFunc("POST /control/polling", s.polling)
	mux.HandleFunc("POST /jobs/{id}/session", s.session)
	mux.HandleFunc("POST /jobs/{id}/report", s.report)
	mux.HandleFunc("POST /jobs/{id}/escalate", s.escalate)
	mux.HandleFunc("POST /jobs/{id}/dropin", s.dropin)
	mux.HandleFunc("POST /jobs/{id}/handback", s.handback)
	mux.HandleFunc("POST /control/gc", s.gc)
	mux.HandleFunc("POST /policies/{owner}/{name}/{policy}/shadow", s.shadow)
	return mux
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	n, err := s.Store.CountOpenEscalations()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, apitypes.Status{
		Paused:          s.Engine.Paused(),
		OpenEscalations: n,
		Repos:           repoStatusDTOs(s.Engine.Statuses()),
	})
}

func (s *Server) enqueue(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Repo     string `json:"repo"`
		PRNumber int    `json:"pr_number"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Repo == "" || req.PRNumber == 0 {
		writeErr(w, http.StatusBadRequest, errors.New("body must be {repo, pr_number}"))
		return
	}
	job, err := s.Engine.EnqueuePR(r.Context(), req.Repo, req.PRNumber)
	if err != nil {
		writeErr(w, http.StatusUnprocessableEntity, err)
		return
	}
	writeJSON(w, http.StatusOK, jobDTO(job))
}

func (s *Server) getJob(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	if r.URL.Query().Get("detail") == "1" {
		s.jobDetail(id, w)
		return
	}
	job, err := s.Store.GetJob(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, err)
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	resp := JobResponse{Job: jobDTO(job)}
	if esc, ok, err := s.Store.OpenEscalationForJob(id); err == nil && ok {
		e := escalationDTO(esc)
		resp.Escalation = &e
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) retry(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	job, err := s.Engine.Retry(r.Context(), id)
	if err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, jobDTO(job))
}

func (s *Server) resolve(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	var req struct {
		Resolution string `json:"resolution"`
		Reason     string `json:"reason"`
		Answer     string `json:"answer"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	if err := s.Esc.Resolve(r.Context(), id, req.Resolution, req.Reason, req.Answer, s.Actor); err != nil {
		switch {
		case errors.Is(err, escalate.ErrUnsupportedResolution):
			writeErr(w, http.StatusBadRequest, err)
		default:
			writeErr(w, http.StatusConflict, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) polling(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Paused bool `json:"paused"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	s.Engine.SetPaused(req.Paused)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func pathID(r *http.Request) (int64, error) {
	return strconv.ParseInt(r.PathValue("id"), 10, 64)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, err error) {
	writeJSON(w, code, map[string]string{"error": err.Error()})
}

func (s *Server) needConsult(w http.ResponseWriter) bool {
	if s.Consult == nil {
		writeErr(w, http.StatusServiceUnavailable, errors.New("consult runner not configured"))
		return false
	}
	return true
}

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	var req struct {
		SessionID string `json:"session_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.SessionID == "" {
		writeErr(w, http.StatusBadRequest, errors.New("body must be {session_id}"))
		return
	}
	if !s.needConsult(w) {
		return
	}
	if err := s.Consult.RegisterSession(id, req.SessionID); err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) report(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	var req struct {
		Verdict string `json:"verdict"`
		Summary string `json:"summary"`
		Details string `json:"details"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Verdict == "" {
		writeErr(w, http.StatusBadRequest, errors.New("body must be {verdict, summary, details}"))
		return
	}
	if !s.needConsult(w) {
		return
	}
	if err := s.Consult.Report(id, req.Verdict, req.Summary, req.Details); err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) escalate(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	var req struct {
		Kind     string `json:"kind"`
		Question string `json:"question"`
		Context  string `json:"context"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Question == "" {
		writeErr(w, http.StatusBadRequest, errors.New("body must be {kind, question, context}"))
		return
	}
	if !s.needConsult(w) {
		return
	}
	if err := s.Consult.EscalateQuestion(id, req.Kind, req.Question, req.Context); err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) dropin(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	if !s.needConsult(w) {
		return
	}
	if err := s.Consult.DropIn(id); err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handback(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	if !s.needConsult(w) {
		return
	}
	if err := s.Consult.Handback(id); err != nil {
		writeErr(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) gc(w http.ResponseWriter, r *http.Request) {
	var req struct {
		JobID int64 `json:"job_id"`
		Force bool  `json:"force"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	if !s.needConsult(w) {
		return
	}
	if req.JobID != 0 {
		if err := s.Consult.GCJob(req.JobID, req.Force); err != nil {
			writeErr(w, http.StatusConflict, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		return
	}
	removed, problems := s.Consult.GCAll()
	writeJSON(w, http.StatusOK, map[string]any{"removed": removed, "problems": problems})
}

func (s *Server) shadow(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, err)
		return
	}
	repo := r.PathValue("owner") + "/" + r.PathValue("name")
	if err := s.Engine.SetShadow(repo, r.PathValue("policy"), req.Enabled); err != nil {
		writeErr(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
