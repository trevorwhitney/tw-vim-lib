package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/actor"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/api"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/config"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/consult"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/engine"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/escalate"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/execx"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/github"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/notify"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/opencode"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/policy"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/store"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/tmuxctl"
	"github.com/trevorwhitney/tw-vim-lib/agentd/pkg/workspace"
)

func main() {
	if err := rootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "agentd:", err)
		os.Exit(1)
	}
}

func rootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "agentd",
		Short:         "Deterministic PR assistant daemon",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.PersistentFlags().String("config", defaultConfigPath(), "path to config file")
	root.AddCommand(serveCmd(), onceCmd(), enqueueCmd(), resolveCmd(), statusCmd(), gcCmd())
	return root
}

func defaultConfigPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return x + "/agentd/config.yaml"
	}
	home, _ := os.UserHomeDir()
	return home + "/.config/agentd/config.yaml"
}

// stack is the assembled daemon: every component wired per config.
type stack struct {
	cfg     *config.Config
	store   *store.Store
	engine  *engine.Engine
	esc     *escalate.Manager
	actor   *actor.Actor
	consult *consult.Runner
}

func buildStack(ctx context.Context, cmd *cobra.Command, dryRun bool) (*stack, error) {
	cfgPath, _ := cmd.Flags().GetString("config")
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return nil, err
	}
	st, err := store.Open(cfg.Database)
	if err != nil {
		return nil, err
	}
	chains := map[string][]policy.WithMeta{}
	for _, r := range cfg.Repositories {
		chain, err := policy.Build(r.Policies)
		if err != nil {
			_ = st.Close()
			return nil, fmt.Errorf("repo %s: %w", r.Repo, err)
		}
		chains[r.Repo] = chain
	}
	gh := github.New(execx.Command)
	n := notify.New(cfg.Notify.Banner, cfg.Notify.BadgeFile)
	act := &actor.Actor{Store: st, GH: gh, DryRun: dryRun, Sleep: time.Sleep}
	esc := &escalate.Manager{
		Store: st, Notify: n,
		RenotifyAfter: time.Duration(cfg.Escalation.RenotifyAfter),
		ParkAfter:     time.Duration(cfg.Escalation.ParkAfter),
		Now:           time.Now,
	}

	locals := map[string]string{}
	for _, r := range cfg.Repositories {
		if r.Local != "" {
			locals[r.Repo] = r.Local
		}
	}
	ws := &workspace.Manager{StateDir: filepath.Dir(cfg.Database), Exec: execx.Run}
	oc := &opencode.CLI{Exec: execx.Run, Bin: cfg.OpencodeBin}
	runner := consult.New(ctx, consult.Deps{
		Store:         st,
		GH:            gh,
		Esc:           esc,
		WS:            ws,
		Tmux:          &tmuxctl.Client{Exec: execx.Run, SocketName: cfg.TmuxSocketName},
		OC:            oc,
		Log:           slog.Default(),
		Socket:        cfg.Socket,
		Session:       cfg.TmuxSession,
		DropinCommand: cfg.DropinCommand,
		Locals:        locals,
	}, cfg.Concurrency)
	esc.Final = runner
	esc.Cont = runner

	eng := &engine.Engine{
		Store:            st,
		GH:               gh,
		Actor:            act,
		Esc:              esc,
		Chains:           chains,
		Consult:          runner,
		OnRestart:        cfg.OnRestart,
		AllowOperatorPRs: cfg.AllowOperatorPRs,
		Log:              slog.Default(),
	}
	return &stack{cfg: cfg, store: st, engine: eng, esc: esc, actor: act, consult: runner}, nil
}

func serveCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "run the daemon",
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
			defer stop()

			s, err := buildStack(ctx, cmd, false)
			if err != nil {
				return err
			}
			defer s.store.Close()

			ln, err := api.Listen(s.cfg.Socket)
			if err != nil {
				return err
			}
			srv := &http.Server{Handler: (&api.Server{
				Engine: s.engine, Esc: s.esc, Actor: s.actor, Store: s.store, Consult: s.consult,
			}).Handler()}
			go func() { _ = srv.Serve(ln) }()
			defer srv.Close()

			slog.Info("agentd serving", "socket", s.cfg.Socket,
				"repos", len(s.cfg.Repositories),
				"poll_interval", time.Duration(s.cfg.PollInterval).String())
			return s.engine.Serve(ctx, time.Duration(s.cfg.PollInterval))
		},
	}
}

func onceCmd() *cobra.Command {
	var dryRun bool
	cmd := &cobra.Command{
		Use:   "once",
		Short: "single poll pass over all repos, then exit",
		RunE: func(cmd *cobra.Command, _ []string) error {
			s, err := buildStack(cmd.Context(), cmd, dryRun)
			if err != nil {
				return err
			}
			defer s.store.Close()

			if err := s.engine.Once(cmd.Context()); err != nil {
				return err
			}
			n, err := s.store.CountOpenEscalations()
			if err != nil {
				return err
			}
			fmt.Printf("pass complete; %d open escalation(s)\n", n)
			for _, rs := range s.engine.Statuses() {
				line := "ok"
				if rs.LastError != "" {
					line = rs.LastError
				}
				fmt.Printf("  %-30s %s\n", rs.Repo, line)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "record write actions without executing them")
	return cmd
}

// socketClient dials the running daemon; used by every non-daemon subcommand.
func socketClient(cmd *cobra.Command) (*api.Client, error) {
	cfgPath, _ := cmd.Flags().GetString("config")
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return nil, err
	}
	return api.NewClient(cfg.Socket), nil
}

func enqueueCmd() *cobra.Command {
	var repo string
	var pr int
	cmd := &cobra.Command{
		Use:   "enqueue",
		Short: "process one PR immediately",
		RunE: func(cmd *cobra.Command, _ []string) error {
			c, err := socketClient(cmd)
			if err != nil {
				return err
			}
			job, err := c.Enqueue(repo, pr)
			if err != nil {
				return err
			}
			fmt.Printf("job %d: %s/%s %s\n", job.ID, job.State, job.Outcome, job.Summary)
			return nil
		},
	}
	cmd.Flags().StringVar(&repo, "repo", "", "owner/name")
	cmd.Flags().IntVar(&pr, "pr", 0, "pull request number")
	_ = cmd.MarkFlagRequired("repo")
	_ = cmd.MarkFlagRequired("pr")
	return cmd
}

func resolveCmd() *cobra.Command {
	var approve, reject, done bool
	var reason, answer string
	cmd := &cobra.Command{
		Use:   "resolve <job-id>",
		Short: "resolve a job's escalation (approve / reject / answer / done)",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			jobID, err := strconv.ParseInt(args[0], 10, 64)
			if err != nil {
				return fmt.Errorf("invalid job id %q", args[0])
			}
			modes := 0
			for _, on := range []bool{approve, reject, answer != "", done} {
				if on {
					modes++
				}
			}
			if modes != 1 {
				return fmt.Errorf("exactly one of --approve, --reject, --answer, --done is required")
			}
			if reject && reason == "" {
				return fmt.Errorf("--reject requires --reason")
			}
			c, err := socketClient(cmd)
			if err != nil {
				return err
			}
			if done {
				return c.Handback(jobID)
			}
			resp, err := c.Job(jobID)
			if err != nil {
				return err
			}
			if resp.Escalation == nil {
				return fmt.Errorf("job %d has no open escalation", jobID)
			}
			switch {
			case approve:
				return c.Resolve(resp.Escalation.ID, "approve", "", "")
			case reject:
				return c.Resolve(resp.Escalation.ID, "reject", reason, "")
			default:
				return c.Resolve(resp.Escalation.ID, "answer", "", answer)
			}
		},
	}
	cmd.Flags().BoolVar(&approve, "approve", false, "approve the attached action (or acknowledge advice)")
	cmd.Flags().BoolVar(&reject, "reject", false, "reject the escalation")
	cmd.Flags().StringVar(&reason, "reason", "", "reason (required with --reject)")
	cmd.Flags().StringVar(&answer, "answer", "", "answer text for a waiting question")
	cmd.Flags().BoolVar(&done, "done", false, "hand an interactive job back to the daemon")
	return cmd
}

func gcCmd() *cobra.Command {
	var jobID int64
	var force bool
	cmd := &cobra.Command{
		Use:   "gc",
		Short: "sweep orphaned worktrees and scratch dirs",
		RunE: func(cmd *cobra.Command, _ []string) error {
			c, err := socketClient(cmd)
			if err != nil {
				return err
			}
			return c.GC(jobID, force)
		},
	}
	cmd.Flags().Int64Var(&jobID, "job", 0, "target a single job's workspace")
	cmd.Flags().BoolVar(&force, "force", false, "remove even with uncommitted changes")
	return cmd
}

func statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status [job-id]",
		Short: "daemon and job status",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			c, err := socketClient(cmd)
			if err != nil {
				return err
			}
			if len(args) == 1 {
				jobID, err := strconv.ParseInt(args[0], 10, 64)
				if err != nil {
					return fmt.Errorf("invalid job id %q", args[0])
				}
				resp, err := c.Job(jobID)
				if err != nil {
					return err
				}
				j := resp.Job
				fmt.Printf("job %d  %s#%d  %s/%s\n  %s\n", j.ID, j.Repo, j.PRNumber, j.State, j.Outcome, j.Summary)
				if resp.Escalation != nil {
					fmt.Printf("  escalation %d (%s): %s\n",
						resp.Escalation.ID, resp.Escalation.Kind, resp.Escalation.Question)
				}
				return nil
			}
			st, err := c.Status()
			if err != nil {
				return err
			}
			fmt.Printf("paused: %v  open escalations: %d\n", st.Paused, st.OpenEscalations)
			for _, r := range st.Repos {
				line := "ok"
				if r.AuthError {
					line = "AUTH ERROR — polling stopped"
				} else if r.LastError != "" {
					line = r.LastError
				}
				fmt.Printf("  %-30s %s\n", r.Repo, line)
			}
			return nil
		},
	}
}
