# TODO: Per-panel opencode session restore tracking

Spec: `docs/superpowers/specs/2026-07-09-opencode-session-restore-tracking-design.md`

## Status
- [x] Root cause investigation
- [x] Design spec (revised after review)
- [x] Implementation plan (revised after review): `docs/superpowers/plans/2026-07-09-opencode-session-restore-tracking.md`
- [x] Implementation
- [x] Tests pass (touched specs green; see Notes on pre-existing failures)
- [x] Lint passes (`make lint-lua`: 0 warnings / 0 errors)

## Implementation tasks (from spec)
- [x] registry.lua: merge-on-upsert (§3a)
- [x] registry.lua: `claimed_session_ids(root, except_key)` (§3b)
- [x] resume.lua: `args_for` accepts + validates `opts.session_id` (§1)
- [x] resume.lua: `capture_session_id(cwd, launch_ts, claimed_ids, opts)` (§2)
- [x] publish.lua: `record` carries `session_id` when non-nil (§4)
- [x] init.lua: record launch_ts (module-level, ms precision) + reset on relaunch (§5a)
- [x] init.lua: capture via publish timer with registry guard + retry cap (§5b, §5c)
- [x] sidebar.lua: thread `session_id` through restore (§6)

## Tests (from spec)
- [x] tests/agent/resume_spec.lua: args_for session_id + capture_session_id cases (21 pass)
- [x] tests/agent/registry_spec.lua: merge upsert + claimed_session_ids (16 pass)
- [x] tests/agent/publish_spec.lua: record forwards/omits session_id; survives exit; timer hook (17 pass)
- [x] tests/agent/init_capture_spec.lua (new): capture orchestration, guard, retry cap, two-panel no-collision, ms-precision, capture_tick (10 pass)

## Notes
- beads is down (Dolt schema-migration panic: "invalid hash length: 11"); tracked here instead.
- Pre-existing headless-environment failures unrelated to this work: sidebar_spec (18) and drawer_spec (1) fail identically at the base commit (401a007). This feature added 64 passing tests and introduced zero new failures.
- Manual verification (needs real opencode TUI, cannot be automated): open two opencode panels in one worktree, confirm `.workmux/agent-sessions.json` has distinct session_id per panel, restore both and confirm each resumes its own session; delete one session out of band and confirm graceful fallback.
