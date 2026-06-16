# Agent Task Description - Implementation Progress

**Plan:** `docs/specs/plans/2026-06-16-agent-task-description.md`  
**Design Spec:** `docs/specs/2026-06-16-agent-task-description-design.md`

## Status: 2 of 10 Tasks Complete (20%)

**Base commit:** 83132af66db46348152f1d8ccf70207520bdae73  
**Latest commit:** 612c308 (docs: mark Tasks 1-2 complete in implementation plan)

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

## ⏳ Remaining Tasks (8 of 10)

### Task 3: Add UTF-8 safe truncation
**Status:** Not started  
**Complexity:** Low (similar to Task 2)  
**Files:** Modify `lua/tw/agent/description.lua`, `test/description_test.lua`

**What it does:**
- Add `truncate(text, max_chars)` function using `vim.fn.strcharpart()` for UTF-8 safety
- Truncate to 30 characters with "..." suffix
- 5 new tests (ASCII, UTF-8, edge cases)

---

### Task 4: Implement generate() with API integration
**Status:** Not started  
**Complexity:** High (async, API integration, error handling)  
**Files:** Modify `lua/tw/agent/description.lua`, create `tests/agent/description_spec.lua`

**What it does:**
- Implement async `generate(buf, callback)` function
- Anthropic API integration via plenary.curl
- Deduplication logic (check loading set)
- API key guard
- Error handling (429 rate limits, network errors, malformed responses)
- Plenary specs for async testing

**Critical details:**
- Use `plenary.curl.post()` with callback
- Model: `claude-3-haiku-20240307`, max_tokens: 30
- Rate limit (429) doesn't cache error (allows retry)
- Other errors cache "error" state

---

### Task 5: Add TermClose cleanup autocmd
**Status:** Not started  
**Complexity:** Low  
**Files:** Modify `lua/tw/agent/description.lua`, `tests/agent/description_spec.lua`

**What it does:**
- Register TermClose autocmd (pattern `agent://*`)
- Call `invalidate(buf)` on terminal close
- Test that cache is cleared on TermClose event

---

### Task 6: Update sidebar to display descriptions
**Status:** Not started  
**Complexity:** Medium (integrates with existing sidebar)  
**Files:** Modify `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What it does:**
- Add `description` field to entries in `collect_entries()`
- Update `render_lines()` to display descriptions (with loading/error states)
- Change default width from 20 to 45
- Add 3 tests for description rendering

**Format:**
- Normal: `"  oc#0  waiting  fixing tests"`
- Loading: `"  oc#0  waiting  ⋯ loading..."`
- Error: `"  oc#0  waiting  ⚠ failed"`

---

### Task 7: Add lazy generation trigger in sidebar refresh
**Status:** Not started  
**Complexity:** Medium (callback coordination)  
**Files:** Modify `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What it does:**
- After `collect_entries()`, check for nil descriptions
- Call `description.generate(buf, callback)` for each nil
- Callback triggers `vim.schedule(M.refresh)` to update UI
- Add 3 tests for lazy generation trigger

---

### Task 8: Run full test suite and verify
**Status:** Not started  
**Complexity:** Low (verification step)

**What it does:**
- Run `make test-lua` (standalone tests)
- Run `make test-plenary` (integration tests)
- Run `make test` (full suite including Go)
- Run `make lint`
- Stage and commit any lint fixes

---

### Task 9: Manual testing with real API
**Status:** Not started  
**Complexity:** Low (manual verification)

**What it does:**
- Set `ANTHROPIC_API_KEY` environment variable
- Test with real agent terminals
- Verify loading state → description flow
- Test error states (invalid key)
- Verify width adjustment
- Document results

---

### Task 10: Update documentation
**Status:** Not started  
**Complexity:** Low (documentation)  
**Files:** Modify `README.md`

**What it does:**
- Add "Agent Sidebar" section to README
- Document features (status, descriptions, loading/error states)
- Configuration instructions (API key setup)
- Troubleshooting section

---

## How to Resume

**For the next session:**

1. **Start with Task 3** - UTF-8 safe truncation (straightforward, builds on Task 2)
2. **Then Task 4** - API integration (most complex, requires plenary specs)
3. **Tasks 5-7** - Integration and sidebar updates
4. **Tasks 8-10** - Verification and documentation

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
- Tests: `test/description_test.lua`, `tests/agent/description_spec.lua` (to be created)
- Sidebar: `lua/tw/agent/sidebar.lua`, `tests/agent/sidebar_spec.lua`

**What's working right now:**
- Description module skeleton with state management
- ANSI stripping and text extraction
- 13 passing unit tests
- All linting passes

**What's next:**
- Add UTF-8 safe truncation (Task 3)
- Then the big one: Anthropic API integration (Task 4)
