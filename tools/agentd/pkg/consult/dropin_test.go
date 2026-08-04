package consult

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/tmuxctl"
)

// tmuxFake implements tmuxctl.Tmux in memory. No argv anywhere: the tmux
// command surface is tmuxctl.Client's concern, tested in its own package.
type tmuxFake struct {
	sessions map[string]bool
	windows  map[string]bool
	created  []map[string]string // session/name/dir/command + env entries
	killed   []string
}

var _ tmuxctl.Tmux = (*tmuxFake)(nil)

func newTmuxFake() *tmuxFake {
	return &tmuxFake{sessions: map[string]bool{}, windows: map[string]bool{}}
}

func (f *tmuxFake) EnsureSession(name string) error {
	f.sessions[name] = true
	return nil
}

func (f *tmuxFake) NewWindow(session, name, dir string, env map[string]string, command string) (string, error) {
	rec := map[string]string{"session": session, "name": name, "dir": dir, "command": command}
	for k, v := range env {
		rec[k] = v
	}
	f.created = append(f.created, rec)
	f.windows["@42"] = true
	return "@42", nil
}

func (f *tmuxFake) HasWindow(windowID string) (bool, error) { return f.windows[windowID], nil }

func (f *tmuxFake) KillWindow(windowID string) error {
	f.killed = append(f.killed, windowID)
	delete(f.windows, windowID)
	return nil
}

func dropinFixture(t *testing.T) (*Runner, *store.Store, *tmuxFake) {
	t.Helper()
	fake := exportFake("{}", nil)
	r, st := fixture(t, fake)
	tf := newTmuxFake()
	r.Tmux = tf
	r.Session = "agents"
	r.DropinCommand = `nvim "+AgentFullscreen opencode"`
	return r, st, tf
}

func waitingJob(t *testing.T, r *Runner, st *store.Store) int64 {
	t.Helper()
	jobID := preparedJob(t, r, st)
	require.NoError(t, st.SetJobState(jobID, "waiting_approval"))
	_, err := st.CreateEscalation(jobID, "waiting_approval", "consult verdict: lgtm", "advice", "", "")
	require.NoError(t, err)
	return jobID
}

func TestDropInMaterializesWindow(t *testing.T) {
	r, st, tf := dropinFixture(t)
	jobID := waitingJob(t, r, st)

	require.NoError(t, r.DropIn(jobID))

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "interactive", job.State)
	require.Equal(t, "@42", job.WindowID)

	require.True(t, tf.sessions["agents"], "drop-in session ensured")
	require.Len(t, tf.created, 1)
	win := tf.created[0]
	require.Equal(t, "agents", win["session"])
	require.Equal(t, job.WorktreePath, win["dir"])
	require.Equal(t, "ses_1", win["AGENTD_SESSION_ID"])
	require.Equal(t, `nvim "+AgentFullscreen opencode"`, win["command"])

	has, err := st.HasEvent(jobID, "dropin")
	require.NoError(t, err)
	require.True(t, has)
}

func TestDropInRequiresSessionAndWaitingState(t *testing.T) {
	r, st, _ := dropinFixture(t)
	jobID := queuedJob(t, st)
	require.Error(t, r.DropIn(jobID), "queued job cannot be dropped into")

	require.NoError(t, st.SetJobState(jobID, "waiting_input"))
	require.Error(t, r.DropIn(jobID), "no session id")
}

func TestHandbackReclaims(t *testing.T) {
	r, st, tf := dropinFixture(t)
	jobID := waitingJob(t, r, st)
	require.NoError(t, r.DropIn(jobID))

	require.NoError(t, r.Handback(jobID))

	job, err := st.GetJob(jobID)
	require.NoError(t, err)
	require.Equal(t, "done", job.State)
	require.Equal(t, "handled", job.Outcome)

	_, open, err := st.OpenEscalationForJob(jobID)
	require.NoError(t, err)
	require.False(t, open, "escalation resolved on hand-back")
	require.Equal(t, []string{"@42"}, tf.killed)
}

func TestSweepInteractiveDetectsClosedWindow(t *testing.T) {
	r, st, tf := dropinFixture(t)
	openJob := waitingJob(t, r, st)
	require.NoError(t, r.DropIn(openJob))

	require.NoError(t, r.SweepInteractive())
	job, err := st.GetJob(openJob)
	require.NoError(t, err)
	require.Equal(t, "interactive", job.State, "live window stays interactive")

	delete(tf.windows, "@42")
	require.NoError(t, r.SweepInteractive())
	job, err = st.GetJob(openJob)
	require.NoError(t, err)
	require.Equal(t, "done", job.State, "closed window is an implicit hand-back")
}
