package api

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
)

const defaultHistoryLimit = 200

func (s *Server) inbox(w http.ResponseWriter, r *http.Request) {
	items, err := s.Store.InboxItems()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, apitypes.InboxResponse{Items: inboxItemDTOs(items)})
}

func (s *Server) fleet(w http.ResponseWriter, r *http.Request) {
	jobs, err := s.Store.NonTerminalJobs()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, apitypes.JobsResponse{Jobs: jobDTOs(jobs)})
}

func (s *Server) jobDetail(id int64, w http.ResponseWriter) {
	job, err := s.Store.GetJob(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeErr(w, http.StatusNotFound, err)
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	d := apitypes.JobDetail{Job: jobDTO(job)}
	if esc, ok, err := s.Store.OpenEscalationForJob(id); err == nil && ok {
		e := escalationDTO(esc)
		d.Escalation = &e
	}
	if ds, err := s.Store.DecisionsForJob(id); err == nil {
		d.Decisions = decisionDTOs(ds)
	}
	if as, err := s.Store.ActionsForJob(id); err == nil {
		d.Actions = actionDTOs(as)
	}
	if es, err := s.Store.EventsForJob(id); err == nil {
		d.Events = eventDTOs(es)
	}
	if xs, err := s.Store.ArtifactsForJob(id); err == nil {
		d.Artifacts = artifactDTOs(xs)
	}
	writeJSON(w, http.StatusOK, d)
}

func (s *Server) history(w http.ResponseWriter, r *http.Request) {
	limit := defaultHistoryLimit
	if q := r.URL.Query().Get("limit"); q != "" {
		if n, err := strconv.Atoi(q); err == nil && n > 0 {
			limit = n
		}
	}
	jobs, err := s.Store.TerminalJobs(limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, apitypes.JobsResponse{Jobs: jobDTOs(jobs)})
}
