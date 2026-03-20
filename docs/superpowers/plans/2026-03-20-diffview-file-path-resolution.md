# Diffview File Path Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When sending context to AI agents from diffview buffers, resolve `diffview://` URIs to real on-disk file paths so the agent can actually read the referenced files.

**Architecture:** Add a `resolve_file_path()` utility to `lua/tw/agent/util.lua` that parses `diffview://` URIs and extracts the real file path + repo root. Update the three Send functions in `lua/tw/agent/init.lua` and `get_buffer_files()` in `util.lua` to use this resolver instead of raw `vim.fn.expand("%")`.

**Tech Stack:** Neovim Lua, plenary.nvim (Path), diffview.nvim URI format

**Spec:** `docs/superpowers/specs/2026-03-20-diffview-file-path-resolution-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lua/tw/agent/util.lua` | Modify | Add `resolve_file_path()`, update `get_buffer_files()` with resolve + dedup |
| `lua/tw/agent/init.lua` | Modify (`SendSelection`, `SendSymbol`, `SendFile` functions) | Update three Send functions to use resolver |
| `test/resolve_file_path_test.lua` | Create | Standalone Lua tests for `resolve_file_path()` |
| `Makefile` | Modify | Add `test-lua` target |

---

### Task 1: Add `resolve_file_path()` + tests

**Files:**
- Modify: `lua/tw/agent/util.lua` (add function before `get_buffer_files`)
- Create: `test/resolve_file_path_test.lua`
- Modify: `Makefile` (add test-lua target)

- [ ] **Step 1: Add the `resolve_file_path` function to util.lua**

Add the following function to `lua/tw/agent/util.lua`, immediately before the `get_buffer_files()` function (before the line `function M.get_buffer_files()`):

```lua
--- Resolve a buffer name to a real, absolute file path.
--- Handles diffview:// URIs by extracting the file path and resolving it
--- against the repo root embedded in the URI.
---
--- Contract: always returns (absolute_path, repo_root) or (nil, nil).
--- Never returns a relative path, empty string, or diffview:// URI.
---
--- This function is side-effect free — no vim.notify, no writes.
---
--- @param bufname string|nil Buffer name (defaults to vim.fn.expand("%"))
--- @return string|nil resolved_path Absolute file path, or nil if unresolvable
--- @return string|nil repo_root Git repo root, or nil (callers fall back to get_git_root())
function M.resolve_file_path(bufname)
    bufname = bufname or vim.fn.expand("%")

    -- Empty or nil buffer name is unresolvable
    if not bufname or bufname == "" then
        return nil, nil
    end

    -- Not a diffview buffer — return as-is (already absolute from expand("%"))
    if not bufname:match("^diffview://") then
        return bufname, nil
    end

    -- Null buffer — no file to reference
    if bufname == "diffview://null" then
        return nil, nil
    end

    -- Strip the diffview:// prefix
    local path = bufname:gsub("^diffview://", "")

    -- Extract repo root and relative file path from URI.
    --
    -- Known diffview URI formats (after stripping diffview://):
    --   Commit: /abs/path/to/repo/.git/<sha-abbrev>/<rel-path>
    --           e.g., /Users/foo/project/.git/abc1234def0/src/bar.lua
    --   Stage:  /abs/path/to/repo/.git/:<N>:/<rel-path>
    --           e.g., /Users/foo/project/.git/:0:/src/bar.lua
    --   Null:   null (handled above)
    --
    -- Source: diffview.nvim/lua/diffview/vcs/file.lua, File:create_buffer()
    --
    -- Uses greedy (.*) match so the LAST .git/ in the path is matched,
    -- handling cases where .git appears in parent directory names.

    -- Try commit rev pattern: .../<repo-root>/.git/<sha>/<rel-path>
    local repo_root, rel_path = path:match("^(.*)/%.git/[^/]+/(.+)$")
    if not rel_path then
        -- Try stage rev pattern: .../<repo-root>/.git/:<N>:/<rel-path>
        repo_root, rel_path = path:match("^(.*)/%.git/:%d+:/(.+)$")
    end

    if not repo_root or not rel_path then
        return nil, nil
    end

    return repo_root .. "/" .. rel_path, repo_root
end
```

- [ ] **Step 2: Create the test file**

Create `test/resolve_file_path_test.lua`. This stubs both `vim` and `plenary.path` so the test runs under plain `lua` without Neovim. We always pass explicit `bufname` arguments so the `vim.fn.expand` stub is never exercised in practice.

```lua
-- Standalone tests for resolve_file_path()
-- Run: lua test/resolve_file_path_test.lua (or via make test-lua)
--
-- Stubs vim and plenary.path so this runs outside Neovim.

-- Stub plenary.path before anything requires it
package.preload["plenary.path"] = function()
    local Path = {}
    Path.__index = Path
    setmetatable(Path, {
        __call = function(cls, _, path_str)
            return setmetatable({ filename = path_str }, cls)
        end,
    })
    function Path:make_relative(root)
        if root and self.filename:sub(1, #root) == root then
            local rel = self.filename:sub(#root + 2) -- skip the trailing /
            return rel
        end
        return self.filename
    end
    function Path:new(path_str)
        return setmetatable({ filename = path_str }, Path)
    end
    return Path
end

-- Minimal vim stub
vim = vim
    or {
        fn = {
            expand = function()
                return ""
            end,
            filereadable = function()
                return 0
            end,
        },
        api = {
            nvim_list_bufs = function()
                return {}
            end,
        },
        bo = setmetatable({}, {
            __index = function()
                return {}
            end,
        }),
    }

-- Adjust package.path to find our module
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local util = require("tw.agent.util")

local pass_count = 0
local fail_count = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        print("  PASS: " .. name)
    else
        fail_count = fail_count + 1
        print("  FAIL: " .. name)
        print("        " .. tostring(err))
    end
end

local function eq(expected, actual, msg)
    if expected ~= actual then
        error(
            (msg or "")
                .. " expected: "
                .. tostring(expected)
                .. ", got: "
                .. tostring(actual)
        )
    end
end

print("resolve_file_path tests:")
print()

test("regular absolute path returns unchanged", function()
    local path, root = util.resolve_file_path("/Users/foo/project/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq(nil, root, "root")
end)

test("commit diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/abc1234def0/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("stage diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/:0:/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("stage 2 diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/:2:/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("null diffview buffer returns nil", function()
    local path, root = util.resolve_file_path("diffview://null")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test("empty string returns nil", function()
    local path, root = util.resolve_file_path("")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test("malformed diffview URI returns nil", function()
    local path, root = util.resolve_file_path("diffview://something-unexpected")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test(".git in parent dir uses last .git anchor", function()
    local path, root = util.resolve_file_path(
        "diffview:///Users/foo/.git-projects/repo/.git/abc123/src/bar.lua"
    )
    eq("/Users/foo/.git-projects/repo/src/bar.lua", path, "path")
    eq("/Users/foo/.git-projects/repo", root, "root")
end)

test("deeply nested file path in commit URI", function()
    local path, root = util.resolve_file_path(
        "diffview:///home/user/work/.git/d4a7b0d/lua/tw/agent/init.lua"
    )
    eq("/home/user/work/lua/tw/agent/init.lua", path, "path")
    eq("/home/user/work", root, "root")
end)

test("full SHA in commit URI", function()
    local path, root = util.resolve_file_path(
        "diffview:///Users/foo/project/.git/abc1234def0abc1234def0abc1234def0abc1234d/src/bar.lua"
    )
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("diffview URI with no rev component returns nil", function()
    local path, root = util.resolve_file_path("diffview:///Users/foo/project/.git/")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

print()
print(string.format("Results: %d passed, %d failed, %d total", pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
```

- [ ] **Step 3: Add `test-lua` target to Makefile**

Add the following target to `Makefile` (after the `format-nix` target). Also add `test-lua` to the `help` output:

In the `help` target, add:
```
	@echo "  test-lua  - Run Lua unit tests"
```

After the last target, add:
```makefile
test-lua:
	@echo "Running Lua tests..."
	@lua test/resolve_file_path_test.lua
```

- [ ] **Step 4: Run tests**

Run: `make test-lua`
Expected: 11 tests PASS, 0 failures

- [ ] **Step 5: Run lint and format**

Run: `make format-lua && make lint-lua`
Expected: PASS. Note: `lint-lua` only checks `lua/` — it does not lint the test file under `test/`.

- [ ] **Step 6: Commit**

```bash
git add lua/tw/agent/util.lua test/resolve_file_path_test.lua Makefile
git commit -m "feat: add resolve_file_path() for diffview URI resolution

Add a utility function that parses diffview:// URIs to extract real
on-disk file paths. Includes standalone Lua unit tests covering commit,
stage, null, malformed, and greedy .git matching cases."
```

---

### Task 2: Update all Send functions and `get_buffer_files()`

**Files:**
- Modify: `lua/tw/agent/init.lua` (`SendSelection`, `SendSymbol`, `SendFile` functions)
- Modify: `lua/tw/agent/util.lua` (`get_buffer_files` function)

All three Send functions follow the same pattern: replace `vim.fn.expand("%")` with `util.resolve_file_path()`, add nil check with early return, and use `repo_root` for `make_relative()`. The `get_buffer_files()` update also hoists `get_git_root()` above the loop to avoid per-buffer subprocess spawning.

- [ ] **Step 1: Replace `SendSelection()` implementation**

Replace the `SendSelection()` function in `lua/tw/agent/init.lua` with:

```lua
function M.SendSelection()
    -- Resolve file path FIRST — bail before any side effects if unresolvable
    local filename, repo_root = util.resolve_file_path()
    if not filename then
        vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
        return
    end

    local git_root = repo_root or util.get_git_root()
    local rel_path = Path:new(filename):make_relative(git_root)

    -- Yank sets the '< and '> marks reliably
    vim.cmd('normal! "sy')

    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")

    -- Exit visual mode before opening agent
    vim.cmd("normal! \027") -- \027 is escape key

    -- Format: @filename:start-end
    local reference
    if start_line == end_line then
        reference = "@" .. rel_path .. ":" .. start_line .. " "
    else
        reference = "@" .. rel_path .. ":" .. start_line .. "-" .. end_line .. " "
    end

    confirmOpenAndDo(function()
        M.SendText({ reference })
    end)
end
```

- [ ] **Step 2: Replace `SendSymbol()` implementation**

Replace the `SendSymbol()` function in `lua/tw/agent/init.lua` with:

```lua
function M.SendSymbol()
    local filename, repo_root = util.resolve_file_path()
    if not filename then
        vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
        return
    end

    local git_root = repo_root or util.get_git_root()
    local rel_path = Path:new(filename):make_relative(git_root)
    local word = vim.fn.expand("<cword>")
    local line_num = vim.fn.line(".")
    confirmOpenAndDo(function()
        M.SendText({
            word .. " @" .. rel_path .. ":" .. line_num .. " ",
        })
    end)
end
```

- [ ] **Step 3: Replace `SendFile()` implementation**

Replace the `SendFile()` function in `lua/tw/agent/init.lua` with:

```lua
function M.SendFile()
    local filename, repo_root = util.resolve_file_path()
    if not filename then
        vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
        return
    end

    local git_root = repo_root or util.get_git_root()
    local rel_path = Path:new(filename):make_relative(git_root)
    confirmOpenAndDo(function()
        M.SendText({
            "@" .. rel_path .. " ",
        })
    end)
end
```

- [ ] **Step 4: Replace `get_buffer_files()` implementation**

Replace the `get_buffer_files()` function in `lua/tw/agent/util.lua` with the following. Note: `get_git_root()` is hoisted above the loop so it's called at most once (not per-buffer):

```lua
function M.get_buffer_files()
    local files = {}
    local seen = {}
    local buffers = vim.api.nvim_list_bufs()
    -- Hoist git root lookup above loop — avoid per-buffer subprocess spawning
    local fallback_root = M.get_git_root()

    for _, buf in ipairs(buffers) do
        if vim.bo[buf].buflisted then
            local name = vim.api.nvim_buf_get_name(buf)
            -- Resolve diffview URIs to real paths before any checks
            local resolved, repo_root = M.resolve_file_path(name)
            if resolved and not seen[resolved] then
                -- Check if resolved path exists on disk
                if vim.fn.filereadable(resolved) == 1 then
                    seen[resolved] = true
                    local git_root = repo_root or fallback_root
                    local rel_path = Path:new(resolved):make_relative(git_root)
                    table.insert(files, "@" .. rel_path)
                end
            end
        end
    end

    return files
end
```

Dedup rationale: diffview creates paired left/right buffers for each file, so the same file can appear as both a real buffer and a diffview buffer. Without dedup, the agent receives duplicate `@file` references.

- [ ] **Step 5: Run lint, format, and tests**

Run: `make format-lua && make lint-lua && make test-lua`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lua/tw/agent/init.lua lua/tw/agent/util.lua
git commit -m "feat: resolve diffview paths in agent context-sending keymaps

Update SendSelection, SendSymbol, SendFile, and get_buffer_files to use
resolve_file_path() so that diffview:// URIs are translated to real
on-disk file paths before being sent to the AI agent."
```

---

### Task 3: Smoke test (manual)

After both commits, verify the feature works end-to-end in Neovim:

- [ ] **Step 1: Open a diffview**

In Neovim, run `<leader>gd`, select a commit, and let diffview open with `DiffviewOpen <sha>..HEAD`.

- [ ] **Step 2: Test from the right-side (HEAD) panel**

Place cursor on the right-side panel (HEAD/working tree), press `<leader>cf`. Verify the sent text uses a real file path like `@src/foo.lua`, not a `diffview://` URI.

- [ ] **Step 3: Test from the left-side (commit) panel**

Place cursor on the left-side panel (commit version), press `<leader>cf`. Verify the sent text uses the real file path (same as the right side).

- [ ] **Step 4: Test visual selection from diffview**

On either side, visually select some lines and press `<leader>c*`. Verify the sent text uses a real file path with line range like `@src/foo.lua:10-20`.

- [ ] **Step 5: Test `<leader>cb` with diffview buffers open**

Press `<leader>cb` to send all open buffers. Verify that diffview buffers are resolved to real paths and deduplicated (the same file should appear only once).
