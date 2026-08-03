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
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

type Server struct {
	Engine *engine.Engine
	Esc    *escalate.Manager
	Actor  *actor.Actor
	Store  *store.Store
}

type StatusResponse struct {
	Paused          bool                `json:"paused"`
	OpenEscalations int                 `json:"open_escalations"`
	Repos           []engine.RepoStatus `json:"repos"`
}

type JobResponse struct {
	Job        store.Job         `json:"job"`
	Escalation *store.Escalation `json:"escalation,omitempty"`
}

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
	mux.HandleFunc("POST /jobs", s.enqueue)
	mux.HandleFunc("GET /jobs/{id}", s.getJob)
	mux.HandleFunc("POST /jobs/{id}/retry", s.retry)
	mux.HandleFunc("POST /escalations/{id}/resolve", s.resolve)
	mux.HandleFunc("POST /control/polling", s.polling)
	return mux
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	n, err := s.Store.CountOpenEscalations()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, StatusResponse{
		Paused:          s.Engine.Paused(),
		OpenEscalations: n,
		Repos:           s.Engine.Statuses(),
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
	writeJSON(w, http.StatusOK, job)
}

func (s *Server) getJob(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err)
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
	resp := JobResponse{Job: job}
	if esc, ok, err := s.Store.OpenEscalationForJob(id); err == nil && ok {
		resp.Escalation = &esc
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
	writeJSON(w, http.StatusOK, job)
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
