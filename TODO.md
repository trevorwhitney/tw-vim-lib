# TODO: consult pipeline + drop-in (Plan 2 of 3)

Plan: `docs/superpowers/plans/2026-08-03-consult-pipeline-dropin.md`
Workflow: prototype-driven subagent development. All 21 tasks implemented,
reviewed (spec + quality per batch), and committed across four repos.

## Batches
- [x] Batch A: Tasks 1-4 (execx, store, github, config/checks) — fd0cc74..020e727
- [x] Batch B: Tasks 5-7 (workspace, tmuxctl, opencode+classify) — f49fafa..5eb18a1
- [x] Batch C: Tasks 8-9 (consult-triage policy, escalate manager) — f75ce4e, 3ff1778
- [x] Batch D: Tasks 10-12 (consult runner, finalize, dropin) — 6e044c3..e363e78
- [x] Batch E: Tasks 13-15 (engine wiring, api endpoints, CLI) — f5c0845..16be8bf
- [x] Batch F: Tasks 16-17 (plugin: tools/register, consult agent+skill) — tw-agent-plugin 6a8b4b5, 514ce9f
- [x] Batch G: Task 18 (nvim identity + AGENTD_SESSION_ID launch) — 9dcad0f
- [x] Batch H: Task 19 (dotfiles oc --session) — dotfiles ccfe58a
- [x] Batch I: Task 20 (acceptance harness) — 2d5551f, b306b0d, ac75337
- [x] Task 21 live smoke fixes: workspace binding — 0a2f769

## /goal checklist (Task 21)
- [x] `make lint` green; `make test-lua`/`test-agentd`/`test-go` green.
      `make test-plenary`: sidebar_spec (18) + drawer_spec (1) + consumers (1)
      fail identically at the base commit — documented pre-existing
      headless-environment failures; zero new failures from this plan.
- [x] Plugin repo: `yarn typecheck` green; `yarn test` 94 passed / 2 skipped.
- [x] `make test-agentd-acceptance` green — all five scenarios, twice
      (before and after the workspace-binding fix).
- [x] Live smoke: 4 real consults against trevorwhitney/agentd-acceptance.
      Real session ids self-registered over the socket; real verdicts with
      analysis; `resolve --approve` posted the mapped comment_pr on PRs
      47/49/50; transcript.json is a real `opencode export`; scratch cleaned.
- [x] Drop-in spot check (operator-verified): window resumed the consult
      session, sidebar showed the agent under the `agentd` project, closing
      the window handed back within one poll (done/handled).
- [x] `oc --session <id>` resumed the correct session when run from the
      job's workspace (with the rtp override until the flake bump).
- [x] Sandbox teardown clean: no open PRs, `agentd gc` clean, no
      agentd-accept tmux server, demo daemons killed.

## Deviations discovered in live smoke (fixed + committed)
- `opencode run` binds its project via `--dir`, not process cwd; the runner
  now passes it (0a2f769). Without it consults ran in the daemon's cwd.
- Inherited `OPENCODE`/`OPENCODE_PID` leak the parent opencode server into
  consults when the daemon is started from inside an opencode session;
  execx now treats an empty env value as unset and jobEnv blanks both.
- `gh pr checks` errors with "no checks reported" on checkless branches;
  Facts now tolerates it (falls back to all-checks rollup) — b306b0d.
- Manual `enqueue` now bypasses the poller defer backoff (Plan 1 follow-up,
  needed for acceptance determinism) — 2d5551f.
- Account-level GitGuardian checks defer fresh PRs and occasionally wedge
  IN_PROGRESS for minutes; the harness waits for check settlement and
  replaces wedged PRs.

## Remaining operator steps
- [x] `make install-agentd` — installed to ~/.local/bin
- [x] dotfiles `home-manager switch` — `oc` is a shell function
- [ ] nvim flake input `github:trevorwhitney/tw-vim-lib` must be bumped after
      this branch merges for drop-in/oc resume to work without the rtp
      override in daily nvim

## Usage notes
- `oc --session <id>` must run from the session's workspace (opencode
  sessions are project-scoped); a finalized job's scratch is already
  removed, so resume applies to live jobs (or export the transcript).

## Follow-ups (review findings accepted at prototype scope)
- [ ] consult: add SetJobStateIf (CAS) — afterExit vs late Report, Handback vs
      Resolve→Finalize are check-then-act races today (code-review important)
- [ ] consult: hbMu does not cover Finalize from Resolve/Reconcile paths
- [ ] consult: FinishJob failure without restart wedges a job in finalizing
- [ ] consult: test the cleanup attention dedup suppress branch + add an
      interleave (-race) test for the report/exit race
- [ ] store: OpenEscalationForJob should ORDER BY + LIMIT 1
- [ ] workspace: PrepareWorktree fetch-fallback can silently build from a
      stale local refs/pull/N/head when origin fetch fails transiently
- [ ] classify: missing confidence unmarshals to 0.0 and passes validation
- [ ] escalate: answer-retry can double-run Continue if record() fails after
      a successful continuation; document/enforce Continuer idempotency
- [ ] api: input-validation errors (reject-without-reason etc.) return 409,
      should be 400
- [ ] transcript.json carries a leading "Exporting session: ..." banner line
      from `opencode export`; strip it if consumers want pure JSON
- [ ] serve shutdown: consider consult.Wait (bounded) before store.Close
- [ ] engine: deferredAt entries are unbounded (Plan 1 carry-over)

# Previous: agentd engine (Plan 1 of 3)

Plan: `docs/superpowers/plans/2026-07-31-agentd-engine.md`
Workflow: prototype-driven subagent development. **COMPLETE** — all 17 tasks implemented,
reviewed (spec + quality per batch), committed, and the dry-run acceptance passed against grafana/loki.

## Follow-ups before arming (removing shadow: true)
- [ ] Actor retry loop should honor ctx cancellation and not retry github.AuthError (actor.go)
- [ ] serve: prefer srv.Shutdown(ctx) over srv.Close() for graceful drain (cmd/agentd/main.go)
- [ ] ChangedFiles truncated heuristic (len>=3000) is undercut by --paginate fetching all pages
- [ ] Validate allowed_paths globs at construction (doublestar.ValidatePattern) instead of
      silently never-matching on a malformed pattern (depupdates.go)
- [ ] deferredAt map is unbounded per-process; prune entries older than deferRecheck if daemon
      outlives prototype scope
- [x] Manual enqueue bypasses the defer backoff (done in Plan 2, 2d5551f)
- [ ] Config for real use: `~/.config/agentd/config.yaml` (sandbox blocked writing it here;
      copy from the demo config, drop the temp-dir database/socket overrides).
      grafana repos need `allowed_authors: ["app/renovate-sh-app"]`.

## Notes
- Plan 1 base commit: da47373; final commit: eaf0522
- Plan 2 base commit: eaf0522; final commit: 0a2f769 (agentd),
  514ce9f (tw-agent-plugin), ccfe58a (dotfiles)

# Previous: Per-panel opencode session restore tracking (complete)

Spec: `docs/superpowers/specs/2026-07-09-opencode-session-restore-tracking-design.md`
All implementation, tests, and lint complete. See git history for details.
