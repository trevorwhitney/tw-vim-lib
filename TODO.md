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
      Pre-existing failures; zero new failures.
      Correction: those 12 were not environmental. They were a stale status
      cache plus assertions left on the pre-3fd2aad one-row sidebar layout,
      root-caused and fixed by `test(agent): repair sidebar spec for the
      two-row layout and status cache`. `make test` now exits 0.
- [x] Manual smoke test in live Neovim (plan Task 6 Step 2), operator-verified:
      close/collapse one of two agent panes and count-less sends route to the
      visible one without reopening; letter picker with both visible;
      vim.ui.select fallback with drawer closed; `1<leader>c*` still
      force-targets.
- [x] Merge/PR decision: merged to main (no PR — solo repo, fast-forward).

