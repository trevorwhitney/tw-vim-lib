package api

import (
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/apitypes"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

func jobDTO(j store.Job) apitypes.Job {
	return apitypes.Job{
		ID: j.ID, Kind: j.Kind, Repo: j.Repo, PRNumber: j.PRNumber,
		HeadSHA: j.HeadSHA, State: j.State, Outcome: j.Outcome,
		Summary: j.Summary, Error: j.Error, WorktreePath: j.WorktreePath,
		SessionID: j.SessionID, WindowID: j.WindowID, VerdictsJSON: j.VerdictsJSON,
		CreatedTS: j.CreatedTS, UpdatedTS: j.UpdatedTS, FinishedTS: j.FinishedTS,
	}
}

func jobDTOs(js []store.Job) []apitypes.Job {
	out := make([]apitypes.Job, 0, len(js))
	for _, j := range js {
		out = append(out, jobDTO(j))
	}
	return out
}

func escalationDTO(e store.Escalation) apitypes.Escalation {
	return apitypes.Escalation{
		ID: e.ID, JobID: e.JobID, TS: e.TS, Kind: e.Kind, Question: e.Question,
		Advice: e.Advice, ActionKind: e.ActionKind, ActionParamsJSON: e.ActionParamsJSON,
		State: e.State, Resolution: e.Resolution, Reason: e.Reason, Answer: e.Answer,
		LastNotifiedTS: e.LastNotifiedTS,
	}
}

func repoStatusDTOs(rs []engine.RepoStatus) []apitypes.RepoStatus {
	out := make([]apitypes.RepoStatus, 0, len(rs))
	for _, r := range rs {
		out = append(out, apitypes.RepoStatus{
			Repo: r.Repo, LastPollTS: r.LastPollTS, LastError: r.LastError, AuthError: r.AuthError,
		})
	}
	return out
}

func decisionDTOs(ds []store.Decision) []apitypes.Decision {
	out := make([]apitypes.Decision, 0, len(ds))
	for _, d := range ds {
		out = append(out, apitypes.Decision{
			ID: d.ID, JobID: d.JobID, TS: d.TS, Policy: d.Policy,
			Classifier: d.Classifier, ClassifierResult: d.ClassifierResult,
			Verdict: d.Verdict, Rationale: d.Rationale,
		})
	}
	return out
}

func actionDTOs(as []store.ActionRead) []apitypes.Action {
	out := make([]apitypes.Action, 0, len(as))
	for _, a := range as {
		out = append(out, apitypes.Action{
			ID: a.ID, JobID: a.JobID, TS: a.TS, Kind: a.Kind, ParamsJSON: a.ParamsJSON,
			Simulated: a.Simulated, ExecutedTS: a.ExecutedTS, Result: a.Result, Error: a.Error,
		})
	}
	return out
}

func eventDTOs(es []store.Event) []apitypes.Event {
	out := make([]apitypes.Event, 0, len(es))
	for _, e := range es {
		out = append(out, apitypes.Event{
			ID: e.ID, JobID: e.JobID, TS: e.TS, Type: e.Type, PayloadJSON: e.PayloadJSON,
		})
	}
	return out
}

func artifactDTOs(as []store.Artifact) []apitypes.Artifact {
	out := make([]apitypes.Artifact, 0, len(as))
	for _, a := range as {
		out = append(out, apitypes.Artifact{ID: a.ID, JobID: a.JobID, Name: a.Name, Path: a.Path})
	}
	return out
}

func inboxItemDTOs(items []store.InboxItem) []apitypes.InboxItem {
	out := make([]apitypes.InboxItem, 0, len(items))
	for _, it := range items {
		out = append(out, apitypes.InboxItem{
			Escalation: escalationDTO(it.Escalation), Job: jobDTO(it.Job),
		})
	}
	return out
}
