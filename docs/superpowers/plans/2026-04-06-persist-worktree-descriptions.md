# Persist Worktree Descriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist LLM-generated worktree descriptions to `worktrees.json` in the parent directory shared by all worktrees, so descriptions survive tmux reboots.

**Architecture:** A new local function `persist_worktree_description` in `lua/tw/agent/init.lua` handles read/upsert/prune/atomic-write of the JSON file. It is called from inside the existing `generate_pane_description` async callback, after the description is validated. The `generate_pane_description` signature gains a `cwd` parameter passed from `WorkmuxPrompt`.

**Tech Stack:** Lua (Neovim runtime), `vim.json.encode`/`vim.json.decode`, Lua `io` library, `os.rename`

**Spec:** `docs/superpowers/specs/2026-04-06-persist-worktree-descriptions-design.md`

**Notes:**
- No `.gitignore` change needed -- `worktrees.json` lives outside any git repo (in the parent of all worktrees).
- Concurrent writes from multiple Neovim instances use last-writer-wins. The atomic rename prevents corruption; a dropped entry self-heals on the next prompt from that worktree.

---

## File Map

- **Modify:** `lua/tw/agent/init.lua`
  - Add `persist_worktree_description` function (new local function, ~35 lines)
  - Modify `generate_pane_description` signature and body
  - Modify `WorkmuxPrompt` call site (one line)

No new tracked source files or modules. One runtime artifact (`worktrees.json`) is produced at `~/workspace/<repo>/worktrees.json`.

---

### Task 1: Add persist_worktree_description and wire it into the existing flow

**Files:**
- Modify: `lua/tw/agent/init.lua`

- [ ] **Step 1: Add the `persist_worktree_description` function**

Insert this function immediately before `generate_pane_description` (before the `--- Generate a short pane description` doc comment):

```lua
--- Persist a worktree description to worktrees.json in the parent directory.
--- Fire-and-forget: errors are logged but never disrupt the user.
--- This function runs synchronously on the main loop; blocking I/O is acceptable
--- because the file is a few hundred bytes at most.
local function persist_worktree_description(worktree_name, parent_dir, desc)
    local path = parent_dir .. "/worktrees.json"
    local tmp_path = parent_dir .. "/worktrees.json.tmp"

    -- Read existing entries
    local entries = {}
    local ok, err = pcall(function()
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            if content and content ~= "" then
                local decoded = vim.json.decode(content)
                if type(decoded) == "table" then
                    entries = decoded
                else
                    log.warn("persist_worktree_description: decoded non-table type, resetting")
                end
            end
        end
    end)
    if not ok then
        log.warn("persist_worktree_description: read/decode failed: " .. tostring(err))
        entries = {}
    end

    -- Upsert
    entries[worktree_name] = desc

    -- Prune entries whose directories no longer exist.
    -- This iterates all keys on every write; acceptable because a repo
    -- typically has only 2-5 worktrees.
    for key, _ in pairs(entries) do
        if vim.fn.isdirectory(parent_dir .. "/" .. key) == 0 then
            entries[key] = nil
        end
    end

    -- Atomic write: tmp file -> rename.
    -- The tmp file uses a fixed name (not PID-suffixed); concurrent writes
    -- to the same .tmp are benign because os.rename is atomic on POSIX.
    local write_ok, write_err = pcall(function()
        local file = io.open(tmp_path, "w")
        if not file then
            error("failed to open tmp file for writing")
        end
        file:write(vim.json.encode(entries))
        file:close()
        local rename_ok, rename_err = os.rename(tmp_path, path)
        if not rename_ok then
            error("rename failed: " .. tostring(rename_err))
        end
    end)
    if not write_ok then
        log.warn("persist_worktree_description: write failed: " .. tostring(write_err))
        pcall(os.remove, tmp_path)
    end
end
```

- [ ] **Step 2: Change `generate_pane_description` signature to accept `cwd`**

Change the function signature from:

```lua
local function generate_pane_description(prompt_text)
```

to:

```lua
local function generate_pane_description(prompt_text, cwd)
```

- [ ] **Step 3: Add worktree path derivation before the async call**

After the `pane_id` nil-guard block (after the `return` for `TMUX_PANE not set`), before the `-- Clear any stale description` comment, add:

```lua
    -- Derive worktree info for file persistence.
    -- Must be captured synchronously here, not inside the async callback,
    -- because the user's cwd could change before the callback fires.
    local worktree_name = cwd and vim.fn.fnamemodify(cwd, ":t") or nil
    local parent_dir = cwd and vim.fn.fnamemodify(cwd, ":h") or nil
    local parent_name = parent_dir and vim.fn.fnamemodify(parent_dir, ":t") or nil
    local is_main_worktree = (worktree_name == parent_name)
```

- [ ] **Step 4: Add persist call in the `vim.schedule` block**

Inside the `vim.schedule` callback, after the `if desc == ""` early return and before the `log.info("generate_pane_description: @desc = " .. desc)` line, add:

```lua
                -- Persist description to worktrees.json (fire-and-forget)
                if worktree_name and parent_dir and not is_main_worktree then
                    persist_worktree_description(worktree_name, parent_dir, desc)
                end
```

Note: the guard checks `worktree_name and parent_dir` so that `cwd` being nil only skips persistence, not the entire function. The existing tmux `@desc` flow continues to work regardless.

- [ ] **Step 5: Update the call site in `WorkmuxPrompt`**

In `WorkmuxPrompt()`, change the `generate_pane_description` call from:

```lua
    generate_pane_description(prompt_text)
```

to:

```lua
    generate_pane_description(prompt_text, cwd)
```

`cwd` is already captured earlier in `WorkmuxPrompt` (`local cwd = vim.fn.getcwd()`), so no new variable is needed.

- [ ] **Step 6: Format and lint**

Run: `make format && make lint`
Expected: PASS (no warnings or errors)

- [ ] **Step 7: Review the diff**

Run: `git diff` to verify:
- `persist_worktree_description` is defined before `generate_pane_description`
- `generate_pane_description` accepts `(prompt_text, cwd)`
- Worktree path derivation happens before the async `vim.system` call
- Persist call is inside the `vim.schedule` block, before the tmux set call, guarded by `worktree_name and parent_dir and not is_main_worktree`
- `WorkmuxPrompt` passes `cwd` as the second argument
- No unrelated changes

- [ ] **Step 8: Commit**

```bash
git add lua/tw/agent/init.lua
git commit -m "feat: persist worktree descriptions to worktrees.json"
```
