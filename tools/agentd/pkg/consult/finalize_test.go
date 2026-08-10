package consult

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
)

// exportFake is an ocFake with a canned Export result.
func exportFake(transcript string, exportErr error) *ocFake {
	return &ocFake{export: transcript, exportErr: exportErr}
}

func preparedJob(t *testing.T, r *Runner, st *store.Store) int64 {
	t.Helper()
	jobID := queuedJob(t, st)
	dir, err := r.prepare(Request{JobID: jobID, Repo: "grafana/loki", Number: 42, Title: "bump x"})
	require.NoError(t, err)
	require.NoError(t, st.SetJobWorktree(jobID, dir))
	require.NoError(t, st.SetJobSessionID(jobID, "ses_1"))
	return jobID
}

func TestFinalizeExportsCleansAndFinishes(t *testing.T) {
	fake := exportFake(`{"messages":[]}`, nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)

	require.NoError(t, r.Finalize(context.Background(), jobID, "done", "acknowledged", "advice acknowledged"))

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acknowledged", job.Outcome)

	transcript := filepath.Join(r.WS.ArtifactDir(jobID), "transcript.json")
	require.FileExists(t, transcript)
	_, statErr := os.Stat(job.WorktreePath)
	require.True(t, os.IsNotExist(statErr), "workspace removed")

	payload, ok, err := st.LatestEventPayload(jobID, "finalizing")
	require.NoError(t, err)
	require.True(t, ok)
	require.Contains(t, payload, `"acknowledged"`)
}

func TestFinalizeDirtyInteractiveWorkspaceRaisesAttention(t *testing.T) {
	fake := exportFake("{}", nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.NoError(t, st.AddEvent(jobID, "dropin", ""))
	require.NoError(t, os.WriteFile(filepath.Join(job.WorktreePath, "real-work.md"), []byte("x"), 0o644))

	require.NoError(t, r.Finalize(context.Background(), jobID, "done", "handled", "resolved interactively"))

	job, err = st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State, "cleanup failure never blocks finish")
	require.DirExists(t, job.WorktreePath, "dirty interactive workspace preserved")

	escs, err := st.OpenEscalations()
	require.NoError(t, err)
	require.Len(t, escs, 1)
	require.Contains(t, escs[0].Question, "uncommitted changes")
}

func TestFinalizeTranscriptFailureIsRecorded(t *testing.T) {
	fake := exportFake("", errors.New("export broke"))
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)

	require.NoError(t, r.Finalize(context.Background(), jobID, "rejected", "rejected", "nope"))

	has, err := st.HasEvent(jobID, "transcript_export_failed")
	require.NoError(t, err)
	require.True(t, has)
	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "rejected", job.State)
}

func TestContinueResumesSession(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, req opencode.Request) (string, error) {
		require.Equal(t, "ses_1", req.SessionID)
		require.Contains(t, req.Prompt, "use main")
		require.NoError(t, r.Report(jobID, "approve", "ok", "d"))
		return "", nil
	}}
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "waiting_input"))

	require.NoError(t, r.Continue(context.Background(), jobID, "use main"))
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State, "continuation delivered a report")
}

func TestReconcileRunningResumes(t *testing.T) {
	fake := &ocFake{onRun: func(r *Runner, jobID int64, req opencode.Request) (string, error) {
		require.Equal(t, "ses_1", req.SessionID, "resume continues the persisted session")
		require.NoError(t, r.Report(jobID, "approve", "ok", "d"))
		return "", nil
	}}
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "running"))

	require.NoError(t, r.Reconcile("resume"))
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "waiting_approval", job.State)
}

func TestReconcileFailModes(t *testing.T) {
	r, st := fixture(t, &ocFake{})
	running := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(running, "running"))
	prep := queuedJob2(t, st, 43)
	require.NoError(t, st.SetJobState(prep, "preparing"))

	require.NoError(t, r.Reconcile("fail"))
	r.Wait()

	for _, id := range []int64{running, prep} {
		job, err := st.GetJob(id)
		require.NoError(t, err)
		require.Equal(t, "failed", job.State)
	}
}

func TestReconcileReplaysFinalizing(t *testing.T) {
	fake := exportFake("{}", nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "finalizing"))
	require.NoError(t, st.AddEvent(jobID, "finalizing", `{"state":"done","outcome":"acted","summary":"merged"}`))

	require.NoError(t, r.Reconcile("resume"))
	r.Wait()

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
}

func TestGC(t *testing.T) {
	r, st := fixture(t, &ocFake{})
	doneJob := preparedJob(t, r, st)
	require.NoError(t, st.FinishJob(doneJob, "done", "acted", "m"))
	liveJob := queuedJob2(t, st, 44)
	dir, err := r.prepare(Request{JobID: liveJob, Repo: "grafana/loki", Number: 44, Title: "t"})
	require.NoError(t, err)
	require.NoError(t, st.SetJobState(liveJob, "running"))

	removed, problems := r.GCAll()
	require.Empty(t, problems)
	require.Len(t, removed, 1)
	require.DirExists(t, dir, "live job's workspace survives the sweep")

	// Targeted force removal of a dirty workspace.
	require.NoError(t, os.WriteFile(filepath.Join(dir, "wip"), []byte("x"), 0o644))
	require.NoError(t, st.FinishJob(liveJob, "done", "acted", "m"))
	require.Error(t, r.GCJob(liveJob, false), "dirty workspace refuses non-forced gc")
	require.NoError(t, r.GCJob(liveJob, true))
	_, statErr := os.Stat(dir)
	require.True(t, os.IsNotExist(statErr))
}

func queuedJob2(t *testing.T, st *store.Store, pr int) int64 {
	t.Helper()
	id, err := st.CreateJob("pr", "grafana/loki", pr, "sha"+strings.Repeat("x", pr%7+1))
	require.NoError(t, err)
	return id
}

func TestContinueRefusesNonWaitingJob(t *testing.T) {
	fake := &ocFake{}
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "running"))

	require.Error(t, r.Continue(context.Background(), jobID, "use main"),
		"a job already continued must refuse a second continuation")
	require.Empty(t, fake.reqs, "no session spawned for a lost claim")
}

func TestFinalizeIsIdempotent(t *testing.T) {
	fake := exportFake("{}", nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)

	require.NoError(t, r.Finalize(context.Background(), jobID, "done", "handled", "first"))
	require.NoError(t, r.Finalize(context.Background(), jobID, "rejected", "rejected", "second"))

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State, "second finalize is a no-op")
	require.Equal(t, "handled", job.Outcome)
}

func TestSweepFinalizingReplaysWedgedJob(t *testing.T) {
	fake := exportFake("{}", nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "finalizing"))
	require.NoError(t, st.AddEvent(jobID, "finalizing", `{"state":"done","outcome":"acted","summary":"merged"}`))

	require.NoError(t, r.SweepFinalizing())

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "acted", job.Outcome)
}

func TestTranscriptStripsExportBanner(t *testing.T) {
	fake := exportFake("Exporting session: ses_1\n{\"messages\":[]}", nil)
	r, st := fixture(t, fake)
	jobID := preparedJob(t, r, st)

	require.NoError(t, r.Finalize(context.Background(), jobID, "done", "acted", "m"))

	b, err := os.ReadFile(filepath.Join(r.WS.ArtifactDir(jobID), "transcript.json"))
	require.NoError(t, err)
	require.True(t, json.Valid(b), "transcript must be pure JSON")
}
