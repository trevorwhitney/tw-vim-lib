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

## vrnsh launcher research
- [x] Inspect `oc`, `:AgentFullscreen`, argument forwarding, and agent command construction.
- [x] Check installed OpenCode, Claude, and Codex CLI interfaces.
- [x] Reserve only the first argument for agent selection; forward all remaining arguments.
- [x] Disable injected Claude/Codex permission flags for fullscreen command launches.
- [x] Ship `vrnsh` with the Vim library's default Nix package.
- [x] Present and approve the bounded implementation design.
- [x] Add tests for launch-context permission defaults and launcher argument forwarding.
- [x] Implement `vrnsh` and include it in the default Nix package.
- [x] Preserve automatic permissions for in-editor launches only.
- [x] Run the full test, lint, and Nix build verification.

## vrnsh Navigator error
- [x] Reproduce the `BufEnter` failure and identify Navigator's invalid option assignment.
- [x] Add a regression test and implement the compatibility fix.
- [x] Run focused and repository verification, then inspect the final diff.

## OpenCode mouse wheel scrolling
- [x] Add regression coverage for OpenCode-only terminal wheel mappings.
- [x] Map wheel events to PageUp and PageDown in OpenCode agent buffers.
- [x] Run focused tests, lint, and final diff verification.

## Global git branch picker keymap
- [x] Add regression coverage for `<leader>gg` before gitsigns loads and in terminal mode.
- [x] Register `<leader>gg` as a Telescope lazy key for normal and terminal modes.
- [x] Run focused and repository verification, then inspect the final diff.

## GitHub Diffview colors
- [x] Identify the GitHub theme highlight causing the incorrect Diffview colors.
- [x] Add a regression test for the GitHub Diffview overrides.
- [x] Configure the GitHub theme for Diffview-compatible highlights.
- [x] Run focused and repository verification, then inspect the final diff.
- [x] Add regression coverage for GitHub-style red/green paired changes.
- [x] Apply side-specific Diffview highlights for GitHub themes.
- [x] Re-run verification and inspect the updated diff.
- [x] Add regression coverage for cycling to unified inline diffs.
- [x] Add `diff1_inline` to the standard Diffview layout cycle.
- [x] Verify the layout configuration and final diff.
