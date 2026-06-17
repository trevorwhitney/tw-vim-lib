# Agent Task Description Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AI-generated task descriptions to the agent sidebar, showing what each agent is working on.

**Architecture:** New `description.lua` module manages LLM interaction and caching. Sidebar calls it lazily to generate descriptions on first display. Uses plenary.curl for async Anthropic API calls with callback-based completion.

**Tech Stack:** Lua, Neovim API, plenary.nvim (curl), Anthropic Claude API (Haiku model)

---

## File Structure

**New Files:**
- `lua/tw/agent/description.lua` - Description generation and caching module

**Modified Files:**
- `lua/tw/agent/sidebar.lua` - Add description column to rendering and lazy generation trigger

**Test Files:**
- `test/agent/description_test.lua` - Standalone unit tests for description module
- `tests/agent/description_spec.lua` - Plenary integration tests
- `tests/agent/sidebar_spec.lua` - Add description rendering tests to existing sidebar specs

---

### Task 1: Create description module skeleton with state management ✅ COMPLETED (commit: 73b2bea)

**Files:**
- Create: `lua/tw/agent/description.lua`
- Test: `test/agent/description_test.lua`

- [x] **Step 1: Write test for get() returning nil for uncached buffer**

Create `test/agent/description_test.lua`:

```lua
-- Standalone unit tests for description module (pure logic, no plenary)
local harness = require("tests.agent.shared_harness")

describe("description module state management", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    description = require("tw.agent.description")
    description._reset_for_test()
  end)

  it("get() returns nil for buffer not in cache or loading", function()
    local result = description.get(123)
    assert.is_nil(result)
  end)
end)
```

- [x] **Step 2: Run test to verify it fails**

Run: `make test-lua`
Expected: FAIL with "module 'tw.agent.description' not found"

- [x] **Step 3: Create description module skeleton**

Create `lua/tw/agent/description.lua`:

```lua
local M = {}

-- Cache mapping buffer number to description string or "error"
local descriptions = {}

-- Set of buffer numbers currently generating descriptions (used as Lua set: buf -> true)
local loading = {}

-- Read API key once at module load to avoid repeated env lookups
local api_key = vim.loop.os_getenv("ANTHROPIC_API_KEY")

-- Synchronous lookup of current description state
-- Returns: nil (not requested), "loading" (in progress), string (description), or "error"
function M.get(buf)
  if loading[buf] then
    return "loading"
  end
  return descriptions[buf]  -- nil, string, or "error"
end

-- Clear cached description for a buffer
function M.invalidate(buf)
  descriptions[buf] = nil
  loading[buf] = nil
end

-- Test-only: reset all state
function M._reset_for_test()
  descriptions = {}
  loading = {}
end

return M
```

- [x] **Step 4: Run test to verify it passes**

Run: `make test-lua`
Expected: PASS

- [x] **Step 5: Write test for get() returning "loading" when buffer in loading set**

Add to `test/agent/description_test.lua`:

```lua
  it("get() returns 'loading' when buffer is in loading set", function()
    description._set_loading_for_test(123, true)
    local result = description.get(123)
    assert.equals("loading", result)
  end)

  it("get() returns cached description when in cache", function()
    description._set_cache_for_test(123, "fixing tests")
    local result = description.get(123)
    assert.equals("fixing tests", result)
  end)

  it("get() returns 'error' when cached as error", function()
    description._set_cache_for_test(123, "error")
    local result = description.get(123)
    assert.equals("error", result)
  end)
```

- [x] **Step 6: Add test helpers to description module**

Add to `lua/tw/agent/description.lua` before `return M`:

```lua
-- Test-only: set loading state
function M._set_loading_for_test(buf, is_loading)
  loading[buf] = is_loading or nil
end

-- Test-only: set cached description
function M._set_cache_for_test(buf, value)
  descriptions[buf] = value
end
```

- [x] **Step 7: Run tests to verify they pass**

Run: `make test-lua`
Expected: All tests PASS

- [x] **Step 8: Write test for invalidate() clearing both cache and loading**

Add to `test/agent/description_test.lua`:

```lua
  it("invalidate() clears both cache and loading state", function()
    description._set_cache_for_test(123, "old description")
    description._set_loading_for_test(456, true)
    
    description.invalidate(123)
    description.invalidate(456)
    
    assert.is_nil(description.get(123))
    assert.is_nil(description.get(456))
  end)
```

- [x] **Step 9: Run tests to verify they pass**

Run: `make test-lua`
Expected: All tests PASS

- [x] **Step 10: Stage changes**

```bash
git add lua/tw/agent/description.lua test/agent/description_test.lua
```

- [x] **Step 11: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [x] **Step 12: Commit after confirmation**

```bash
git commit -m "feat(agent): add description module skeleton with state management"
```

---

### Task 2: Add ANSI stripping and text extraction ✅ COMPLETED (commit: f7a76ba)

**Files:**
- Modify: `lua/tw/agent/description.lua`
- Test: `test/description_test.lua` (moved from test/agent/)

- [x] **Step 1: Write test for ANSI stripping**

Add to `test/agent/description_test.lua`:

```lua
describe("description ANSI stripping", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    description = require("tw.agent.description")
  end)

  it("strips CSI sequences", function()
    local input = "\27[31mred text\27[0m normal"
    local result = description._strip_ansi_for_test(input)
    assert.equals("red text normal", result)
  end)

  it("strips OSC sequences with BEL terminator", function()
    local input = "text\27]0;title\7more"
    local result = description._strip_ansi_for_test(input)
    assert.equals("textmore", result)
  end)

  it("strips OSC sequences with ST terminator", function()
    local input = "text\27]0;title\27\\more"
    local result = description._strip_ansi_for_test(input)
    assert.equals("textmore", result)
  end)

  it("handles text with no ANSI codes", function()
    local input = "plain text"
    local result = description._strip_ansi_for_test(input)
    assert.equals("plain text", result)
  end)
end)
```

- [x] **Step 2: Run tests to verify they fail**

Run: `make test-lua`
Expected: FAIL with "attempt to call field '_strip_ansi_for_test'"

- [x] **Step 3: Implement ANSI stripping function**

Add to `lua/tw/agent/description.lua` after `api_key` definition:

```lua
-- Strip ANSI escape sequences from text
-- Pattern adapted from status.lua:strip_ansi()
local function strip_ansi(s)
  -- CSI: ESC [ <params/intermediates> <final-byte>
  s = s:gsub("\27%[[%d;:%?%>%<]*[ -/]*[A-Za-z@%[\\%]^_`{|}~]", "")
  -- OSC: ESC ] <anything except BEL or ESC> <terminator>
  -- Terminators: BEL (\7) or ESC \ (ST)
  s = s:gsub("\27%][^\7\27]*\7", "")
  s = s:gsub("\27%][^\27]*\27\\", "")
  -- Two-byte ESC sequences: ESC <single letter or = > >
  s = s:gsub("\27[=>%(%)#%*+%-./]", "")
  return s
end
```

Add test helper before `return M`:

```lua
-- Test-only: expose ANSI stripping
function M._strip_ansi_for_test(s)
  return strip_ansi(s)
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `make test-lua`
Expected: All tests PASS

- [x] **Step 5: Write test for text extraction from buffer**

Add to `test/agent/description_test.lua`:

```lua
describe("description text extraction", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    description = require("tw.agent.description")
  end)

  it("extracts first 75 lines from buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, 100 do
      table.insert(lines, "line " .. i)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    local result = description._extract_text_for_test(buf)
    local result_lines = vim.split(result, "\n")
    
    -- Should be 75 lines joined
    assert.equals(75, #result_lines)
    assert.equals("line 1", result_lines[1])
    assert.equals("line 75", result_lines[75])
    
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips ANSI codes from extracted text", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "\27[31mred\27[0m",
      "plain text",
    })
    
    local result = description._extract_text_for_test(buf)
    assert.is_true(result:find("red") ~= nil)
    assert.is_nil(result:find("\27"))
    
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles buffers with fewer than 75 lines", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })
    
    local result = description._extract_text_for_test(buf)
    local result_lines = vim.split(result, "\n")
    
    assert.equals(2, #result_lines)
    
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string for invalid buffer", function()
    local result = description._extract_text_for_test(99999)
    assert.equals("", result)
  end)
end)
```

- [x] **Step 6: Run tests to verify they fail**

Run: `make test-lua`
Expected: FAIL with "attempt to call field '_extract_text_for_test'"

- [x] **Step 7: Implement text extraction function**

Add to `lua/tw/agent/description.lua` after `strip_ansi` function:

```lua
-- Extract first 75 lines from terminal buffer and strip ANSI codes
-- Returns joined text or empty string if buffer invalid
local function extract_text(buf)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, 75, false)
  if not ok or not lines then
    return ""
  end
  local joined = table.concat(lines, "\n")
  return strip_ansi(joined)
end
```

Add test helper before `return M`:

```lua
-- Test-only: expose text extraction
function M._extract_text_for_test(buf)
  return extract_text(buf)
end
```

- [x] **Step 8: Run tests to verify they pass**

Run: `make test-lua`
Expected: All tests PASS

- [x] **Step 9: Stage changes**

```bash
git add lua/tw/agent/description.lua test/agent/description_test.lua
```

- [x] **Step 10: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [x] **Step 11: Commit after confirmation**

```bash
git commit -m "feat(agent): add ANSI stripping and text extraction to description module"
```

---

### Task 3: Add UTF-8 safe truncation ✅ COMPLETED (commit: e729a8e)

**Files:**
- Modify: `lua/tw/agent/description.lua`
- Test: `test/description_test.lua`

- [x] **Step 1: Write tests for UTF-8 safe truncation**

Add to `test/agent/description_test.lua`:

```lua
describe("description truncation", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    description = require("tw.agent.description")
  end)

  it("truncates ASCII text at 30 chars", function()
    local input = "this is a very long description that exceeds thirty characters"
    local result = description._truncate_for_test(input, 30)
    assert.equals("this is a very long descri...", result)
    assert.equals(30, vim.fn.strchars(result))
  end)

  it("does not truncate text shorter than limit", function()
    local input = "short text"
    local result = description._truncate_for_test(input, 30)
    assert.equals("short text", result)
  end)

  it("handles text exactly at limit", function()
    local input = "exactly thirty characters!!!!!"
    local result = description._truncate_for_test(input, 30)
    assert.equals("exactly thirty characters!!!!!", result)
  end)

  it("handles UTF-8 multi-byte characters safely", function()
    local input = "测试中文字符串that is very long"
    local result = description._truncate_for_test(input, 20)
    -- Should not break mid-character
    assert.equals(20, vim.fn.strchars(result))
    assert.is_true(result:sub(-3) == "...")
  end)

  it("handles empty string", function()
    local result = description._truncate_for_test("", 30)
    assert.equals("", result)
  end)
end)
```

- [x] **Step 2: Run tests to verify they fail**

Run: `make test-lua`
Expected: FAIL with "attempt to call field '_truncate_for_test'"

- [x] **Step 3: Implement UTF-8 safe truncation function**

Add to `lua/tw/agent/description.lua` after `extract_text` function:

```lua
-- Truncate text to max_chars, respecting UTF-8 boundaries
-- Appends "..." if truncated. Uses character count, not byte count.
local function truncate(text, max_chars)
  local char_count = vim.fn.strchars(text)
  if char_count <= max_chars then
    return text
  end
  
  -- Truncate to (max_chars - 3) to leave room for "..."
  -- vim.fn.strcharpart is UTF-8 aware
  local truncated = vim.fn.strcharpart(text, 0, max_chars - 3)
  return truncated .. "..."
end
```

Add test helper before `return M`:

```lua
-- Test-only: expose truncation
function M._truncate_for_test(text, max_chars)
  return truncate(text, max_chars)
end
```

- [x] **Step 4: Run tests to verify they pass**

Run: `make test-lua`
Expected: All tests PASS

- [x] **Step 5: Stage changes**

```bash
git add lua/tw/agent/description.lua test/description_test.lua
```

- [x] **Step 6: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [x] **Step 7: Commit after confirmation**

```bash
git commit -m "feat(agent): add UTF-8 safe truncation to description module"
```

---

### Task 4: Implement generate() with API integration

**Files:**
- Modify: `lua/tw/agent/description.lua`
- Test: `tests/agent/description_spec.lua` (plenary, for async testing)

- [ ] **Step 1: Write plenary spec for generate() deduplication**

Create `tests/agent/description_spec.lua`:

```lua
local helpers = require("tests.agent.spec_helpers")

describe("description generation", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    helpers.reset_and_mock(false)
    description = require("tw.agent.description")
    description._reset_for_test()
  end)

  it("generate() returns immediately if already loading", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local call_count = 0
    
    -- Mock plenary.curl to track calls
    package.loaded["plenary.curl"] = {
      post = function()
        call_count = call_count + 1
      end
    }
    
    -- Simulate buffer already loading
    description._set_loading_for_test(buf, true)
    
    -- Should be no-op
    description.generate(buf, function() end)
    
    assert.equals(0, call_count)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() returns immediately if API key missing", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local callback_called = false
    
    -- Force API key to be nil
    description._set_api_key_for_test(nil)
    
    description.generate(buf, function()
      callback_called = true
    end)
    
    assert.is_false(callback_called)
    assert.is_nil(description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-plenary`
Expected: FAIL with "attempt to call field 'generate'"

- [ ] **Step 3: Implement generate() skeleton**

Add to `lua/tw/agent/description.lua` after `truncate` function:

```lua
-- Async generate description for buffer using Anthropic API
-- Calls callback(description_or_error) when complete
-- No-op if already loading or API key missing
function M.generate(buf, callback)
  -- Guard: already loading this buffer
  if loading[buf] then
    return
  end
  
  -- Guard: API key not configured
  if not api_key or api_key == "" then
    return
  end
  
  -- Mark as loading before async work
  loading[buf] = true
  
  -- Extract text from buffer
  local text = extract_text(buf)
  if text == "" then
    -- Invalid buffer or empty content
    descriptions[buf] = "error"
    loading[buf] = nil
    if callback then
      callback("error")
    end
    return
  end
  
  -- TODO: Make API request (next step)
end
```

Add test helper before `return M`:

```lua
-- Test-only: override API key
function M._set_api_key_for_test(key)
  api_key = key
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-plenary`
Expected: Tests PASS (deduplication and missing key guards work)

- [ ] **Step 5: Write plenary spec for successful API response**

Add to `tests/agent/description_spec.lua`:

```lua
  it("generate() caches result on successful API response", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "working on tests" })
    
    description._set_api_key_for_test("test-key")
    
    -- Mock plenary.curl success
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        -- Simulate async callback
        vim.schedule(function()
          opts.callback({
            status = 200,
            body = vim.json.encode({
              content = {{ text = "testing feature" }}
            })
          })
        end)
      end
    }
    
    local callback_result = nil
    description.generate(buf, function(result)
      callback_result = result
    end)
    
    -- Wait for async
    vim.wait(100, function() return callback_result ~= nil end)
    
    assert.equals("testing feature", callback_result)
    assert.equals("testing feature", description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
```

- [ ] **Step 6: Implement API request logic**

Add to `lua/tw/agent/description.lua`, replace the `-- TODO: Make API request` comment:

```lua
  -- Build API request
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    descriptions[buf] = "error"
    loading[buf] = nil
    if callback then
      callback("error")
    end
    return
  end
  
  local request_body = vim.json.encode({
    model = "claude-3-haiku-20240307",
    max_tokens = 30,
    messages = {{
      role = "user",
      content = "Summarize what this agent/terminal is doing in 4-5 words:\n\n" .. text
    }}
  })
  
  curl.post("https://api.anthropic.com/v1/messages", {
    headers = {
      ["x-api-key"] = api_key,
      ["anthropic-version"] = "2023-06-01",
      ["content-type"] = "application/json",
    },
    body = request_body,
    timeout = 10000,
    callback = function(response)
      vim.schedule(function()
        -- Remove from loading set
        loading[buf] = nil
        
        -- Handle response
        if response.status == 200 then
          local ok_parse, data = pcall(vim.json.decode, response.body)
          if ok_parse and data.content and data.content[1] and data.content[1].text then
            local desc = vim.trim(data.content[1].text)
            desc = truncate(desc, 30)
            descriptions[buf] = desc
            if callback then
              callback(desc)
            end
          else
            -- Malformed response
            descriptions[buf] = "error"
            if callback then
              callback("error")
            end
          end
        elseif response.status == 429 then
          -- Rate limit: don't cache error, allow retry
          if callback then
            callback(nil)
          end
        else
          -- Other error
          descriptions[buf] = "error"
          if callback then
            callback("error")
          end
        end
      end)
    end,
  })
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 8: Write spec for error handling**

Add to `tests/agent/description_spec.lua`:

```lua
  it("generate() caches error on API failure", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })
    
    description._set_api_key_for_test("test-key")
    
    -- Mock plenary.curl error
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        vim.schedule(function()
          opts.callback({ status = 500, body = "error" })
        end)
      end
    }
    
    local callback_result = nil
    description.generate(buf, function(result)
      callback_result = result
    end)
    
    vim.wait(100, function() return callback_result ~= nil end)
    
    assert.equals("error", callback_result)
    assert.equals("error", description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() does not cache error on rate limit (429)", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })
    
    description._set_api_key_for_test("test-key")
    
    -- Mock plenary.curl rate limit
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        vim.schedule(function()
          opts.callback({ status = 429, body = "rate limited" })
        end)
      end
    }
    
    local callback_result = "not called"
    description.generate(buf, function(result)
      callback_result = result
    end)
    
    vim.wait(100, function() return callback_result ~= "not called" end)
    
    assert.is_nil(callback_result)
    assert.is_nil(description.get(buf))  -- Not cached
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 10: Stage changes**

```bash
git add lua/tw/agent/description.lua tests/agent/description_spec.lua
```

- [ ] **Step 11: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [ ] **Step 12: Commit after confirmation**

```bash
git commit -m "feat(agent): implement generate() with Anthropic API integration"
```

---

### Task 5: Add TermClose cleanup autocmd

**Files:**
- Modify: `lua/tw/agent/description.lua`
- Test: `tests/agent/description_spec.lua`

- [ ] **Step 1: Write spec for TermClose autocmd**

Add to `tests/agent/description_spec.lua`:

```lua
describe("description cleanup", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    helpers.reset_and_mock(false)
    description = require("tw.agent.description")
    description._reset_for_test()
  end)

  it("TermClose autocmd invalidates cache", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "terminal"
    
    -- Set a cached description
    description._set_cache_for_test(buf, "test description")
    assert.equals("test description", description.get(buf))
    
    -- Simulate TermClose
    vim.api.nvim_exec_autocmds("TermClose", {
      buffer = buf,
      pattern = "agent://*",
    })
    
    -- Should be cleared
    assert.is_nil(description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-plenary`
Expected: FAIL (autocmd not registered)

- [ ] **Step 3: Add TermClose autocmd registration**

Add to `lua/tw/agent/description.lua` before `return M`:

```lua
-- Register cleanup autocmd on module load
local augroup = vim.api.nvim_create_augroup("tw_agent_description_cleanup", { clear = true })
vim.api.nvim_create_autocmd("TermClose", {
  group = augroup,
  pattern = "agent://*",
  callback = function(args)
    M.invalidate(args.buf)
  end,
  desc = "Clear description cache when agent terminal exits",
})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 5: Stage changes**

```bash
git add lua/tw/agent/description.lua tests/agent/description_spec.lua
```

- [ ] **Step 6: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [ ] **Step 7: Commit after confirmation**

```bash
git commit -m "feat(agent): add TermClose autocmd for description cleanup"
```

---

### Task 6: Update sidebar to display descriptions

**Files:**
- Modify: `lua/tw/agent/sidebar.lua:3-20` (DEFAULTS), `lua/tw/agent/sidebar.lua:348-381` (collect_entries), `lua/tw/agent/sidebar.lua:383-397` (render_lines)
- Test: `tests/agent/sidebar_spec.lua`

- [ ] **Step 1: Write spec for description field in entries**

Add to `tests/agent/sidebar_spec.lua` in the "sidebar rendering" describe block:

```lua
  it("collect_entries includes description field", function()
    local buf, job = setup_alive_instance("opencode", 0)
    
    -- Mock description module
    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "fixing tests"
        end
        return nil
      end
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    local entries = sidebar._state().entries
    assert.is_true(#entries >= 1)
    assert.equals("fixing tests", entries[1].description)
  end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-plenary`
Expected: FAIL (description field not present)

- [ ] **Step 3: Update collect_entries to add description field**

In `lua/tw/agent/sidebar.lua`, modify the `collect_entries` function around line 369:

Find this block:
```lua
				table.insert(entries, {
					mode = mode,
					idx = idx,
					status = s,
					buf = inst.buf,
					is_active = (mode == agent.active_mode and idx == agent.active_index),
				})
```

Replace with:
```lua
				local desc = nil
				local ok_desc, description = pcall(require, "tw.agent.description")
				if ok_desc and description and description.get then
					desc = description.get(inst.buf)
				end
				
				table.insert(entries, {
					mode = mode,
					idx = idx,
					status = s,
					buf = inst.buf,
					is_active = (mode == agent.active_mode and idx == agent.active_index),
					description = desc,
				})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-plenary`
Expected: Test PASS

- [ ] **Step 5: Write spec for description rendering in sidebar**

Add to `tests/agent/sidebar_spec.lua`:

```lua
  it("render_lines includes description in output", function()
    local buf, job = setup_alive_instance("opencode", 0)
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "fixing tests"
        end
        return nil
      end
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(#lines >= 3)
    assert.is_true(lines[3]:find("fixing tests") ~= nil)
  end)

  it("render_lines shows loading state", function()
    local buf, job = setup_alive_instance("opencode", 0)
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "loading"
        end
        return nil
      end
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("loading") ~= nil)
  end)

  it("render_lines shows error state", function()
    local buf, job = setup_alive_instance("opencode", 0)
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "error"
        end
        return nil
      end
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("failed") ~= nil)
  end)
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `make test-plenary`
Expected: FAIL (descriptions not rendered)

- [ ] **Step 7: Update render_lines to include description**

In `lua/tw/agent/sidebar.lua`, modify the `render_lines` function around line 394:

Find this block:
```lua
	for _, e in ipairs(entries) do
		local icon = icons[e.status] or "?"
		local mode_short = abbrev[e.mode] or e.mode
		table.insert(lines, string.format("%s %s#%d  %s", icon, mode_short, e.idx, e.status))
	end
```

Replace with:
```lua
	for _, e in ipairs(entries) do
		local icon = icons[e.status] or "?"
		local mode_short = abbrev[e.mode] or e.mode
		local desc_str = ""
		if e.description == "loading" then
			desc_str = "  ⋯ loading..."
		elseif e.description == "error" then
			desc_str = "  ⚠ failed"
		elseif e.description and e.description ~= "" then
			desc_str = "  " .. e.description
		end
		table.insert(lines, string.format("%s %s#%d  %s%s", icon, mode_short, e.idx, e.status, desc_str))
	end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 9: Update default width**

In `lua/tw/agent/sidebar.lua`, modify the `DEFAULTS` table around line 5:

Find:
```lua
	width = 20,
```

Replace with:
```lua
	width = 45,
```

- [ ] **Step 10: Stage changes**

```bash
git add lua/tw/agent/sidebar.lua tests/agent/sidebar_spec.lua
```

- [ ] **Step 11: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [ ] **Step 12: Commit after confirmation**

```bash
git commit -m "feat(agent): render descriptions in sidebar with loading/error states"
```

---

### Task 7: Add lazy generation trigger in sidebar refresh

**Files:**
- Modify: `lua/tw/agent/sidebar.lua:452-504` (refresh function)
- Test: `tests/agent/sidebar_spec.lua`

- [ ] **Step 1: Write spec for lazy generation trigger**

Add to `tests/agent/sidebar_spec.lua`:

```lua
describe("sidebar lazy description generation", function()
  local sidebar, agent

  before_each(function()
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.agent.description"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    agent = helpers.reset_and_mock(false)
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({})
    pcall(sidebar.close)
  end)
  after_each(function() pcall(sidebar.close) end)

  it("refresh() calls generate() for nil descriptions", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test content" })
    agent._set_instance("opencode", 0, buf, 9001)
    
    local generate_called = false
    local generate_buf = nil
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        return nil  -- Simulate not yet requested
      end,
      generate = function(b, callback)
        generate_called = true
        generate_buf = b
      end,
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    assert.is_true(generate_called)
    assert.equals(buf, generate_buf)
  end)

  it("refresh() does not call generate() for cached descriptions", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 9001)
    
    local generate_called = false
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        return "cached description"
      end,
      generate = function(b, callback)
        generate_called = true
      end,
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    vim.fn.jobwait = orig
    
    assert.is_false(generate_called)
  end)

  it("generate() callback triggers sidebar refresh", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })
    agent._set_instance("opencode", 0, buf, 9001)
    
    local stored_callback = nil
    local get_return = nil
    
    package.loaded["tw.agent.description"] = {
      get = function(b)
        return get_return
      end,
      generate = function(b, callback)
        stored_callback = callback
      end,
    }
    
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    
    sidebar.open()
    sidebar.refresh()
    
    -- Simulate async completion
    get_return = "new description"
    if stored_callback then
      stored_callback("new description")
    end
    
    -- Give scheduled callback time to run
    vim.wait(50)
    
    vim.fn.jobwait = orig
    
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("new description") ~= nil)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-plenary`
Expected: FAIL (generate not called)

- [ ] **Step 3: Add lazy generation trigger to refresh()**

In `lua/tw/agent/sidebar.lua`, modify the `refresh` function. After the `collect_entries()` call around line 475, add:

```lua
	local entries = collect_entries()
	local lines = render_lines(entries)
	
	-- Lazy generation: trigger for entries with nil descriptions
	local ok_desc, description = pcall(require, "tw.agent.description")
	if ok_desc and description and description.generate then
		for _, e in ipairs(entries) do
			if e.description == nil then
				description.generate(e.buf, function(result)
					vim.schedule(function()
						M.refresh()
					end)
				end)
			end
		end
	end
	
```

Place this code right after `local lines = render_lines(entries)` and before `vim.bo[state.buf].modifiable = true`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 5: Stage changes**

```bash
git add lua/tw/agent/sidebar.lua tests/agent/sidebar_spec.lua
```

- [ ] **Step 6: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [ ] **Step 7: Commit after confirmation**

```bash
git commit -m "feat(agent): add lazy description generation trigger in sidebar refresh"
```

---

### Task 8: Run full test suite and verify

**Files:**
- All test files

> **Cleanup note (added during Task 3 review):** The `_for_test` helper-exposure
> pattern in `description.lua` is NOT a codebase convention — no other module uses
> it. The analogous `status.lua` keeps `strip_ansi`/helpers as private locals and
> tests them through the public `M.detect()`, exposing only lifecycle methods
> (`detect`, `invalidate`, `reset`). `init.lua`/`sidebar.lua` use the
> `M._foo = local_fn` single-underscore alias convention. During this task, refactor
> `description.lua` to match: rename `_reset_for_test` -> public `M.reset()` (like
> `status.reset()`), convert helper exposure to single-underscore aliases or test
> `strip_ansi`/`extract_text`/`truncate` through `generate()`+`get()`, and drop the
> `_set_loading_for_test`/`_set_cache_for_test` state pokes now that `generate()`
> can drive state.

- [ ] **Step 1: Run all Lua unit tests**

Run: `make test-lua`
Expected: All tests PASS

- [ ] **Step 2: Run all Plenary integration tests**

Run: `make test-plenary`
Expected: All tests PASS

- [ ] **Step 3: Run full test suite**

Run: `make test`
Expected: All tests PASS (Lua, Plenary, and Go)

- [ ] **Step 4: Run linter**

Run: `make lint`
Expected: No errors

- [ ] **Step 5: Stage any lint fixes if needed**

```bash
git add -u
```

- [ ] **Step 6: Commit lint fixes if any**

```bash
git commit -m "chore: fix lint issues"
```

(Skip if no lint issues)

---

### Task 9: Manual testing with real API

**Files:**
- None (manual testing)

- [ ] **Step 1: Set ANTHROPIC_API_KEY environment variable**

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

- [ ] **Step 2: Launch Neovim with test config**

```bash
nvim
```

- [ ] **Step 3: Open an agent terminal**

Run in Neovim:
```vim
:AgentOpen opencode
```

Type a test prompt like "help me fix the failing tests"

- [ ] **Step 4: Open the sidebar**

Press `<leader>\` or run:
```vim
:AgentSidebar
```

- [ ] **Step 5: Verify loading state appears**

Confirm "⋯ loading..." appears next to the agent entry

- [ ] **Step 6: Wait for description to generate**

After a few seconds, verify the description updates from "⋯ loading..." to actual text

- [ ] **Step 7: Test with multiple agents**

Open 2-3 more agents with different prompts and verify descriptions generate for each

- [ ] **Step 8: Test error state**

Temporarily set invalid API key:
```bash
export ANTHROPIC_API_KEY="invalid"
```

Open a new agent and verify "⚠ failed" appears

- [ ] **Step 9: Test width adjustment**

Verify the sidebar is wider (45 chars) and descriptions fit without clipping

- [ ] **Step 10: Document manual test results**

Create a note in commit message or docs summarizing manual test findings

---

### Task 10: Update documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write documentation section for agent descriptions**

Add to `README.md` in an appropriate section (create "Agent Sidebar" section if needed):

```markdown
## Agent Sidebar

The agent sidebar displays all active agent sessions with real-time status and AI-generated task descriptions.

### Features

- **Status Indicators**: Visual icons show whether each agent is working or waiting
- **Task Descriptions**: Brief AI-generated summaries of what each agent is working on
- **Loading States**: See when descriptions are being generated
- **Error States**: Visual feedback when description generation fails

### Configuration

Set your Anthropic API key to enable task descriptions:

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

If the API key is not set, the sidebar still works but descriptions will be blank.

### Customization

```lua
require("tw.agent.sidebar").setup({
  width = 45,  -- Default width to accommodate descriptions
  -- ... other options
})
```

### Troubleshooting

**Descriptions show "⚠ failed":**
- Check that `ANTHROPIC_API_KEY` is set correctly
- Verify network connectivity to api.anthropic.com
- Check for rate limiting (429 errors will auto-retry)

**Descriptions are blank:**
- Ensure `ANTHROPIC_API_KEY` environment variable is set
- Restart Neovim after setting the key
```

- [ ] **Step 2: Stage documentation changes**

```bash
git add README.md
```

- [ ] **Step 3: Pause for human review (required stop)**

Review staged changes and STOP. Do not commit. Wait for explicit human confirmation to continue.

- [ ] **Step 4: Commit after confirmation**

```bash
git commit -m "docs: add agent sidebar task description documentation"
```

---

## Summary

This plan implements AI-generated task descriptions for the agent sidebar in 10 tasks:

1. **State management** - Description cache and loading tracking
2. **Text extraction** - ANSI stripping and buffer reading
3. **Truncation** - UTF-8 safe text truncation
4. **API integration** - Anthropic Claude API with plenary.curl
5. **Cleanup** - TermClose autocmd for cache invalidation
6. **Sidebar display** - Render descriptions with states
7. **Lazy generation** - Trigger on first display
8. **Test suite** - Verify all tests pass
9. **Manual testing** - Real API testing
10. **Documentation** - User-facing docs

Each task follows TDD (test first, implement, verify) with required human review pauses before commits.
