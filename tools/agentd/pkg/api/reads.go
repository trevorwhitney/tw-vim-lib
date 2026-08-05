package api

import (
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
