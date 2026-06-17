# Agent Task Description - Implementation Progress

**Plan:** `docs/specs/plans/2026-06-16-agent-task-description.md`  
**Design Spec:** `docs/specs/2026-06-16-agent-task-description-design.md`

## Status: 9 of 10 Tasks Complete (90%) — Task 9 manual test in progress

**Base commit:** 83132af66db46348152f1d8ccf70207520bdae73  
**Latest commit:** beac934 (fix(agent): use current Anthropic model and log API failures)

All code, automated tests, and documentation are complete. Manual testing
(Task 9) surfaced a real bug, now fixed.

### Task 9 finding (fixed)

First manual test showed `⚠ failed` for all descriptions. Root cause (confirmed
by reproducing the request via `curl`): the model `claude-3-haiku-20240307` is
**retired** and returns HTTP 404, which `generate()` cached as `"error"`.

- **Fix (commit beac934):** switched to `claude-haiku-4-5-20251001` (verified
  against the live API: HTTP 200 with the expected `content[1].text` shape),
  added `tw.log.warn` on non-200/429 responses so failures are diagnosable, and
  added a regression test pinning the request model.
- **Still TODO:** re-run the interactive manual test (Task 9 checklist below)
  with the fix in place to confirm the loading→description flow end-to-end.
  (A headless live test could not complete here due to a sandbox filesystem
  restriction on plenary.curl temp files — not a plugin issue.)
- Available models can be listed with:
  `curl -s https://api.anthropic.com/v1/models -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01"`

---

## ✅ Completed Tasks

### Task 1: Create description module skeleton with state management
**Commit:** 73b2bea  
**Files Created:**
- `lua/tw/agent/description.lua` - State management (cache, loading set, get/invalidate functions)
- `test/agent/description_test.lua` - 5 passing unit tests

**What works:**
- `get(buf)` - Returns nil, "loading", description string, or "error"
- `invalidate(buf)` - Clears cache and loading state
- Test helpers for state manipulation
- All 5 tests passing

---

### Task 2: Add ANSI stripping and text extraction  
**Commit:** f7a76ba  
**Files Modified:**
- `lua/tw/agent/description.lua` - Added `strip_ansi()` and `extract_text()` functions
- `test/description_test.lua` - Moved from `test/agent/` and added 8 new tests

**What works:**
- `strip_ansi(text)` - Removes CSI, OSC (BEL/ST), and two-byte ANSI escape sequences
- `extract_text(buf)` - Reads first 75 lines, strips ANSI, handles invalid buffers
- Test helpers expose both functions
- All 13 tests passing (5 state + 8 ANSI/extraction)

**Code quality fixes applied:**
- Fixed `api_key` variable naming (removed underscore)
- Simplified `vim.split` test stub
- Improved comment hygiene (describes what, not implementation)

---

### Task 3: Add UTF-8 safe truncation
**Commit:** e729a8e  
**Files Modified:**
- `lua/tw/agent/description.lua` - Added `truncate()` function
- `test/description_test.lua` - Added 5 new tests + `vim.fn`/`vim.trim` stubs

**What works:**
- `truncate(text, max_chars)` - UTF-8 safe via `vim.fn.strchars()`/`vim.fn.strcharpart()`
- Appends "..." (counted within the limit), returns unchanged if within limit
- All 18 description tests passing (5 new truncation + 13 existing); 87 total Lua tests pass

**Review note:**
- Confirmed the `_for_test` exposure pattern is NOT a codebase convention. `status.lua`
  (the analogous module) tests helpers through public `M.detect()` and exposes only
  `detect`/`invalidate`/`reset`. `init.lua`/`sidebar.lua` use `M._foo = local_fn`
  single-underscore aliases. Decision: leave `_for_test` in place through Tasks 3-7,
  then refactor in Task 8 (note added to plan).

---

### Task 4: Implement generate() with API integration
**Commit:** 84f5bbd  
**Files:** `lua/tw/agent/description.lua`, `tests/agent/description_spec.lua` (new)

**What works:**
- Async `M.generate(buf, callback)` with dedup guard, API key guard, empty-buffer guard
- Anthropic API via `plenary.curl.post()` (model `claude-3-haiku-20240307`, max_tokens 30)
- Response handling in `vim.schedule`: 200 → trim+truncate+cache; 429 → no cache (retryable); other → cache "error"
- 5 plenary specs (dedup, missing key, success, error, 429)

---

### Task 5: Add TermClose cleanup autocmd
**Commit:** b38b35c  
**Files:** `lua/tw/agent/description.lua`, `tests/agent/description_spec.lua`, `test/description_test.lua`

**What works:**
- TermClose autocmd (pattern `agent://*`) calls `invalidate(args.buf)` on terminal close
- 1 plenary spec verifying cache clear
- Standalone harness gained `nvim_create_augroup`/`nvim_create_autocmd` stubs (module now
  registers an autocmd at load). Spec triggers via buffer name match (nvim_exec_autocmds
  rejects buffer+pattern together).

---

### Task 6: Update sidebar to display descriptions
**Commit:** 1fb125b  
**Files:** `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What works:**
- `collect_entries()` adds `description` field (via `pcall(require, "tw.agent.description")`)
- `render_lines()` shows description / `⋯ loading...` / `⚠ failed`
- Default width 20 → 45
- 4 specs (field present, normal render, loading, error)

---

### Task 7: Add lazy generation trigger in sidebar refresh
**Commit:** cb92ad5  
**Files:** `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What works:**
- After `collect_entries()`, `refresh()` calls `description.generate(buf, cb)` for nil descriptions
- Callback does `vim.schedule(M.refresh)`; loading/cache guards prevent an infinite loop
- 3 specs (triggers on nil, skips cached, callback refreshes UI)

---

### Task 8: Run full test suite and verify + refactor _for_test
**Commits:** cb92ad5 (suite passing), bf60fc5 (refactor)  
**Files:** `lua/tw/agent/description.lua`, `test/description_test.lua`, `tests/agent/description_spec.lua`

**What works:**
- Full `make test` (Lua + Plenary + Go) green; `make lint` clean; `make format` no-op
- Refactored the non-idiomatic `_for_test` seams to match codebase conventions:
  `_reset_for_test` → public `M.reset()` (mirrors `status.reset()`); helpers exposed as
  single-underscore seams (`M._strip_ansi`, `M._extract_text`, `M._truncate`,
  `M._set_loading`, `M._set_cache`, `M._set_api_key`)

---

### Task 10: Update documentation
**Commit:** c2e16c7  
**Files:** `README.md`

**What works:**
- New "Agent Sidebar" README section: features (status icons, descriptions,
  loading/error states), toggling keymaps (`<leader>cv`, `<leader>\`),
  configuration via `require("tw.agent").setup({ sidebar = ... })`, and
  troubleshooting. Details verified against the code (width 45, glyphs,
  429 retry behavior).

---

## ⏳ Remaining Tasks (1 of 10)

### Task 9: Manual testing with real API
**Status:** Deferred to human (cannot be automated)  
**Complexity:** Low (manual verification)

**What it does:**
- Set `ANTHROPIC_API_KEY` environment variable
- Test with real agent terminals
- Verify loading state → description flow
- Test error states (invalid key)
- Verify width adjustment
- Document results

---

## How to Resume

**Only Task 9 remains** — manual testing with a real `ANTHROPIC_API_KEY` at an
interactive Neovim session. Suggested checklist:

1. `export ANTHROPIC_API_KEY="..."` then launch `nvim`.
2. Open an agent (e.g. opencode), type a prompt, then toggle the sidebar with
   `<leader>cv` (or the drawer with `<leader>\`).
3. Confirm `⋯ loading...` appears, then resolves to a short description.
4. Open 2-3 agents with different prompts; confirm each generates.
5. Set an invalid key, open a new agent, confirm `⚠ failed`.
6. Confirm the sidebar width (45) fits descriptions without clipping.

All implementation, automated tests, and documentation are complete
(Tasks 1-8, 10). Only manual verification (Task 9) remains.

**Commands to run:**
```bash
# Check current state
git log --oneline -5
git status

# Run tests
make test-lua
make test-plenary
make lint

# View plan
cat docs/specs/plans/2026-06-16-agent-task-description.md

# View this progress summary
cat docs/specs/plans/2026-06-16-agent-task-description-PROGRESS.md
```

**Key files to know:**
- Implementation: `lua/tw/agent/description.lua`
- Tests: `test/description_test.lua` (standalone), `tests/agent/description_spec.lua` (plenary)
- Sidebar: `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What's working right now:**
- Full description module: state management, ANSI stripping, text extraction,
  UTF-8 truncation, async Anthropic API generation, TermClose cleanup autocmd
- Sidebar renders descriptions with loading/error states and lazily triggers generation
- Test seams follow codebase conventions (`M.reset()`, `M._foo` single-underscore)
- All automated tests pass (Lua + Plenary + Go); `make lint`/`make format` clean
- README documents the feature

**What's next:**
- Task 9: manual testing with a real `ANTHROPIC_API_KEY` (see resume checklist above)
