# TODO: agent send target routing

Plan: `docs/superpowers/plans/2026-08-12-agent-send-target-routing.md`
Workflow: prototype-driven subagent development. All 5 implementation tasks
done, reviewed (spec + quality per task), and committed: c27edf3..3cf3054.

## Verification
- [x] `make lint` exit 0 (0 warnings / 0 errors, 71 files); `make test-lua`
      exit 0 (13 files, includes the new window_picker 12/12); `make test-go`
      exit 0.
- [x] `make test-plenary`: 236 passing at HEAD vs 218 at base d21282a; the
      only failures are sidebar_spec's 12, and the failing-test-name sets at
      HEAD and at a d21282a worktree are byte-identical (`diff` clean).
      Pre-existing headless-environment failures; zero new failures.
- [x] Manual smoke test in live Neovim (plan Task 6 Step 2), operator-verified:
      close/collapse one of two agent panes and count-less sends route to the
      visible one without reopening; letter picker with both visible;
      vim.ui.select fallback with drawer closed; `1<leader>c*` still
      force-targets.
- [x] Merge/PR decision: merged to main (no PR — solo repo, fast-forward).

# TODO: productionize + harden (Plan 4)

Plan: `docs/superpowers/plans/2026-08-06-agentd-productionize-harden.md` (vault symlink, not committed)
Workflow: prototype-driven subagent development

## Tasks
- [x] Task 1: tracking — 2e1b03b
- [x] Task 2: actor retry honors ctx / AuthError — b4662b4
- [x] Task 3: allowed_paths glob validation — 1514998
- [x] Task 4: ChangedFiles truncation vs expected count — e22bcdd
- [x] Task 5: deferredAt pruning — cf4ede2
- [x] Task 6: graceful serve shutdown + consult WaitTimeout — 614308d
- [x] Task 7: store ClaimJobState + OpenEscalationForJob determinism — 4c77547
- [x] Task 8: escalate.Create claims the job state — dde472e
- [x] Task 9: finMu + idempotent Finalize + SweepFinalizing — 7b245f8
- [x] Task 10: Continue claims the waiting state — 7b245f8, bb51501
- [x] Task 11: api 400/503 for validation errors — 83f8989
- [x] Task 12: PrepareWorktree origin-aware fallback — 4f7d167
- [x] Task 13: classify requires confidence — 9aae777
- [x] Task 14: transcript export banner strip — 6440530
- [x] Task 15: race/dedup tests + -race in make test-agentd — 976bdab
- [x] Task 15b: merge-dependency-updates acceptance scenarios (real PRs: shadow, armed, escalate) — 35d5f1a
- [x] Task 16: agentd nix package; remove install-agentd + plist — 21480c8
- [x] Task 17: full verification pass
- [x] Task 18: GATE — merged to main and pushed (origin/main f70561c)
- [x] Task 19: dotfiles agentd module + config — dotfiles branch
      `agentd-launchd` (a5b4aad): agentd.nix launchd module, config.yaml
      (shadow, grafana/loki, app/renovate-sh-app), flake graft + neovim input
      bump to f70561c; `darwin-rebuild build` green. Committed on a worktree
      branch to avoid colliding with in-flight switchyard work on master.
- [ ] Task 20: deploy + stray-daemon cleanup + verify (operator)
- [ ] Task 21: agentmux live click-through (operator)
- [ ] Task 22: shadow observation, then arm (operator)
- [ ] Task 23: bookkeeping (roadmap + TODO follow-ups)

## /goal checklist
- [x] `make lint` green (0 warnings / 0 errors, 70 files)
- [x] `make test-agentd` green under `-race` (17 pkgs)
- [x] `cd tools/agentd && go build ./...` green; agentmux build + tests green
- [x] `nix build .#agentd` green; `result/bin/agentd --help` lists serve/once/enqueue/resolve/status/gc
- [x] `nix build .#agentmux` still green
- [x] No install-agentd/plist stragglers:
      `grep -rn "install-agentd\|io.twhitney.agentd" . | grep -v docs/` empty (outside this tracking note)
- [x] `make test-agentd-acceptance` green — all 8 scenarios (5 consult + 3 new
      merge-dependency-updates) against real PRs in
      trevorwhitney/agentd-acceptance: shadow recorded the merge without merging
      (PR stayed OPEN), armed actually merged the PR on GitHub, out-of-allowed-paths
      escalated with the merge action attached and reject left the PR OPEN.
      Sandbox left clean: no open PRs, no leaked branches (cleanup now deletes
      merged-PR head branches too). Rerun once before treating a failure as
      real (GitGuardian can wedge fresh PRs IN_PROGRESS).

## Follow-ups (review findings accepted at prototype scope)
- [ ] consult: exportTranscript trusts the banner-strip heuristic; consider a
      json.Valid guard before writing transcript.json (silent corruption if the
      banner format ever gains a { or [ before the JSON)
- [ ] acceptance: ocFake is not concurrency-safe (unsynchronized reqs slice);
      guard with a mutex before adding tests where racing paths call OC.Run
- [ ] store/escalate: the claimable-state set ("queued","preparing","running")
      and isTerminal are two halves of one state-machine partition maintained
      in separate places; a named claimableStates var would make the coupling
      visible

# TODO: agentmux mission control (Plan 3 of 3)

Plan: `docs/superpowers/plans/2026-08-05-agentmux-mission-control.md`
Workflow: prototype-driven subagent development. **COMPLETE** — all 20 tasks
implemented, reviewed (spec + quality per task), and committed. Consumes the
agentd apitypes contract + read endpoints from Plan 2b — agentmux is a pure
socket client, no SQLite.

## Batches
- [x] Batch A: Task 1 (depend on agentd/pkg/apitypes via local replace)
- [x] Batch B: Task 2 (socket client — reads + mutations)
- [x] Batch C: Tasks 3-5 (roles/styles, tab enum, tab scaffolding)
- [x] Batch D: Tasks 6-8 (inbox row, refresh/view, mutations)
- [x] Batch E: Tasks 9-10 (fleet row/header, view/keys)
- [x] Batch F: Task 11 (history row/view/keys)
- [x] Batch G: Task 12 (detail panel)
- [x] Batch H: Tasks 13-16 (fuzzy, palette, search, cross-session jump)
- [x] Batch I: Tasks 17-20 (main wiring, help, vendorHash, TODO)

## /goal checklist
- [x] `cd tools/agentmux && go build ./... && go test ./...` green
- [x] `make lint` green
- [x] Socket client imports only stdlib + apitypes (no store/engine/api):
      `go list -deps ./internal/socket/ | grep -E 'pkg/(store|engine|consult|api)$'` empty
- [x] `nix build .#agentmux` green; `result/bin/agentmux -h` lists `-socket`
- [ ] Live check against a running agentd: Inbox lists open escalations,
      approve/reject/answer post over the socket and re-query on ACK, Fleet
      shows non-terminal jobs + poller health, History detail renders the
      decision chain, ⌃P palette runs actions, ? search unions tabs + mirror,
      Interactive tab behaves exactly as before, cross-session drop-in jump works.

# TODO: agentd apitypes + read endpoints (Plan 2b)

Plan: `docs/superpowers/plans/2026-08-05-agentd-apitypes-read-endpoints.md`
Workflow: prototype-driven subagent development. **COMPLETE** — all 10 tasks
implemented, reviewed (spec + quality per task), and committed.

Purpose: decouple agentmux (Plan 3) from agentd's SQLite schema and file paths.
agentd now exposes a dependency-free `pkg/apitypes` wire contract and read
endpoints (`/inbox`, `/fleet`, `/history`, `/jobs/{id}?detail=1`); the client
imports only apitypes. agentmux becomes a pure socket client.

## Tasks
- [x] Batch A: Tasks 1-2 (apitypes DTOs + route constants) — 7c37af5, b111cec
- [x] Batch B: Tasks 3-4 (store TerminalJobs/InboxItems + decisions/actions/events) — 310c62e, b95aa72
- [x] Batch C: Tasks 5-6 (convert mappers + migrate endpoints/client to apitypes) — 33777bc, f63ea7f
- [x] Batch D: Tasks 7-8 (/inbox /fleet /history + /jobs/{id}?detail=1) — 464f609, aea2b0e
- [x] Batch E: Tasks 9-10 (verification, tracking)

## /goal checklist
- [x] `cd tools/agentd && go build ./... && go test ./...` green (17 pkgs)
- [x] `make lint` green (0 warnings/errors); gofmt clean
- [x] Client layering guard: `pkg/api/client.go` imports only stdlib + apitypes
- [x] Wire format unchanged: existing `api_test.go` passes unmodified
- [~] Acceptance suite skipped by operator decision — Plan 2b changed no daemon
      behavior (read-only additions + transparent type migration), so the
      end-to-end suite adds little over the unchanged api_test.go regression guard.

## Follow-up
- [ ] Revise Plan 3 (agentmux mission control): delete its Batch A (SQLite
      reader) and Batch B (duplicate socket client). agentmux imports
      `agentd/pkg/apitypes` and uses the read client methods
      (Inbox/Fleet/History/JobDetail) + existing mutation methods. main.go
      drops DB-path resolution; only the socket path remains.
- [ ] (Optional hardening) jobDetail child-collection reads are best-effort
      (empty slice on DB error, 200 not 500). Fine for a read-only detail view;
      add a logger to the api Server if partial failures should be visible.

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
- [x] consult: add SetJobStateIf (CAS) — closed by Plan 4 Tasks 7-8
      (store.ClaimJobState + escalate.Create claim)
- [x] consult: hbMu does not cover Finalize from Resolve/Reconcile paths —
      closed by Plan 4 Task 9 (finMu)
- [x] consult: FinishJob failure without restart wedges a job in finalizing —
      closed by Plan 4 Task 9 (SweepFinalizing)
- [x] consult: test the cleanup attention dedup suppress branch + add an
      interleave (-race) test for the report/exit race — Plan 4 Task 15
- [x] store: OpenEscalationForJob should ORDER BY + LIMIT 1 — Plan 4 Task 7
- [x] workspace: PrepareWorktree fetch-fallback can silently build from a
      stale local refs/pull/N/head — Plan 4 Task 12
- [x] classify: missing confidence unmarshals to 0.0 and passes validation —
      Plan 4 Task 13
- [x] escalate: answer-retry can double-run Continue — Plan 4 Task 10
      (Continue claims the waiting state; Continuer contract documented)
- [x] api: input-validation errors return 409, should be 400 — Plan 4 Task 11
- [x] transcript.json export banner strip — Plan 4 Task 14
- [x] serve shutdown: consult.Wait (bounded) before store.Close — Plan 4 Task 6
- [x] engine: deferredAt entries are unbounded — Plan 4 Task 5

# Previous: agentd engine (Plan 1 of 3)

Plan: `docs/superpowers/plans/2026-07-31-agentd-engine.md`
Workflow: prototype-driven subagent development. **COMPLETE** — all 17 tasks implemented,
reviewed (spec + quality per batch), committed, and the dry-run acceptance passed against grafana/loki.

## Follow-ups before arming (removing shadow: true)
- [x] Actor retry loop should honor ctx cancellation and not retry github.AuthError — Plan 4 Task 2
- [x] serve: prefer srv.Shutdown(ctx) over srv.Close() for graceful drain — Plan 4 Task 6
- [x] ChangedFiles truncated heuristic (len>=3000) undercut by --paginate — Plan 4 Task 4
- [x] Validate allowed_paths globs at construction — Plan 4 Task 3
- [x] deferredAt map is unbounded per-process — Plan 4 Task 5
- [x] Manual enqueue bypasses the defer backoff (done in Plan 2, 2d5551f)
- [ ] Config for real use: lands in dotfiles as `agentd/config.yaml` via home-manager
      (Plan 4 Task 19); grafana repos need `allowed_authors: ["app/renovate-sh-app"]`.

## Notes
- Plan 1 base commit: da47373; final commit: eaf0522
- Plan 2 base commit: eaf0522; final commit: 0a2f769 (agentd),
  514ce9f (tw-agent-plugin), ccfe58a (dotfiles)

# Previous: Per-panel opencode session restore tracking (complete)

Spec: `docs/superpowers/specs/2026-07-09-opencode-session-restore-tracking-design.md`
All implementation, tests, and lint complete. See git history for details.
