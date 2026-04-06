# Persist Worktree Descriptions to worktrees.json

## Problem

`generate_pane_description` produces a short LLM-generated summary of each worktree's purpose and sets it as the tmux pane-local variable `@desc`. This information is lost when tmux restarts because pane-local variables are not persisted.

## Goal

Persist worktree descriptions to a `worktrees.json` file in the parent directory shared by all worktrees for a repository. The file is populated as a side effect of the existing tmux pane description flow -- it is only written when a workmux prompt triggers `generate_pane_description` inside a tmux session. After a tmux reboot, the file provides a quick reference of what each worktree is doing.

Example for `~/workspace/tw-vim-lib/worktrees.json`:

```json
{
  "kind-mesa": "persist worktree descriptions",
  "flat-hawk": "refactor authentication system",
  "solid-moon": "add user config page"
}
```

The main branch worktree (whose name matches the parent directory, e.g., `tw-vim-lib/tw-vim-lib`) is excluded since it does not represent feature work. This is a convention-based heuristic that depends on the directory layout described below. It is not enforced by git metadata. Non-standard layouts may cause false positives (feature worktree skipped) or false negatives (main worktree included). This is accepted as a known limitation for this scope.

## Design

### Directory Convention

This feature assumes worktrees are structured as:

```
~/workspace/<repo>/
  <repo>/          # main branch (name matches parent)
  <worktree-1>/    # feature worktree
  <worktree-2>/    # feature worktree
  worktrees.json   # <-- new file, lives here
```

The file lives outside any git repository (in the parent of all worktrees), so `.gitignore` is not a concern.

### New Function: `persist_worktree_description(worktree_name, parent_dir, desc)`

A new local function in `lua/tw/agent/init.lua`, placed near `generate_pane_description`. This function is not intended to be called from other locations; the sanitization and path contracts described below are guaranteed by the single call site inside `generate_pane_description`.

**Parameters:**
- `worktree_name` (string): basename of the worktree root directory (e.g., `kind-mesa`)
- `parent_dir` (string): absolute path to the parent directory (e.g., `/Users/foo/workspace/tw-vim-lib`)
- `desc` (string): the LLM-generated description. By the time this function is called, `desc` is guaranteed to be a non-empty, control-character-free string of at most 50 characters (sanitized in `generate_pane_description` after the `desc = vim.trim(...)` / `desc:gsub(...)` / `desc:sub(1, 50)` sequence). No additional sanitization is needed.

**Logic:**

1. **Read**: Open `parent_dir .. "/worktrees.json"` using `io.open(path, "r")`. If the file does not exist (nil return), start with an empty table `{}`. If the file exists, read its contents and `vim.json.decode` into a Lua table. If decode fails, or if the decoded value is not a table (`type(entries) ~= "table"`), log a warning and start with an empty table `{}`.
2. **Upsert**: Set `entries[worktree_name] = desc`.
3. **Prune**: Iterate all keys in the table. For each key, check if `parent_dir .. "/" .. key` exists as a directory (`vim.fn.isdirectory`). Remove entries whose directories no longer exist on disk. Pruning runs on every write; this is acceptable because the number of worktrees per repo is expected to remain small (typically 2-5).
4. **Write atomically**: Encode the table via `vim.json.encode`, write to a temporary file (`worktrees.json.tmp`) using `io.open(tmp_path, "w")` + `file:write()` + `file:close()`, then `os.rename(tmp_path, path)` to atomically replace the target. This prevents a crash or interruption from leaving a partial/corrupt file. The temp file uses a fixed name (not PID-suffixed); concurrent writes to the same `.tmp` are benign because `os.rename` is atomic on POSIX and the `.tmp` is not the source of truth.

All file I/O uses Lua's `io.open`/`io.close` wrapped in `pcall`. Failures are logged via `log.warn` but never propagate -- same fire-and-forget philosophy as the rest of `generate_pane_description`. If the temp file write or rename fails, the temp file is cleaned up via `os.remove` in a pcall.

This function runs synchronously inside a `vim.schedule` callback (i.e., on the Neovim main loop). Blocking I/O is acceptable here because the file is a few hundred bytes at most.

### Concurrency

Multiple Neovim instances (one per worktree) can run `generate_pane_description` concurrently at startup. The read-modify-write cycle is not locked. **Last writer wins.** This is acceptable because:

- The data is ephemeral and regenerative -- each entry is recreated whenever a workmux prompt runs.
- The atomic rename ensures the file is never left in a corrupt partial-write state.
- In the worst case, a concurrent write drops one entry, which self-heals on that worktree's next prompt. A concurrent write can also resurrect a pruned entry for a recently-deleted worktree; this is transient and will be re-pruned by the next persist call from any live worktree.

### Changes to `generate_pane_description`

The function signature changes to accept `cwd` as a parameter: `generate_pane_description(prompt_text, cwd)`. The caller (`WorkmuxPrompt`) already has `cwd` captured and passes it through, avoiding a redundant `vim.fn.getcwd()` call that could diverge if the user changes directories between the two calls. The `cwd` parameter is required; if absent/nil the function returns early (same as the existing `prompt_text` nil guard).

**Before the async `vim.system` call** (where `pane_id` is already captured), derive the worktree and parent paths from `cwd`. Since `WorkmuxPrompt` opens vim at the worktree root and the `.workmux/PROMPT-*.md` lookup at that cwd must succeed for `generate_pane_description` to be called at all, `cwd` is reliably the worktree root directory:

```lua
local worktree_name = vim.fn.fnamemodify(cwd, ":t")
local parent_dir = vim.fn.fnamemodify(cwd, ":h")
local parent_name = vim.fn.fnamemodify(parent_dir, ":t")
local is_main_worktree = (worktree_name == parent_name)
```

**Inside the `vim.schedule` block** of the opencode LLM callback, after `desc` has been validated and sanitized (after the `if desc == ""` early return) but **before** the `vim.system({ "tmux", "set", ... })` call. The persist call does not depend on tmux succeeding -- the file is the source-of-truth fallback for when tmux state is lost:

```lua
if not is_main_worktree then
    persist_worktree_description(worktree_name, parent_dir, desc)
end

-- existing tmux set call follows
log.info("generate_pane_description: @desc = " .. desc)
vim.system({ "tmux", "set", "-pt", pane_id, "@desc", desc }, ...)
```

This ensures:
- Directory values are captured synchronously at call time (before the user might change directories).
- The file write happens once we have a validated description, independent of tmux success.
- The persist call lives in the `vim.schedule` block scope (not nested inside the tmux callback), keeping nesting manageable.

### Error Handling

- **File missing**: Start with empty table (normal first-run case).
- **JSON decode failure** (corrupted file): Log warning, start with empty table. The atomic write replaces the corrupted file with valid content.
- **JSON decode success but non-table type** (e.g., array, string): Log warning, start with empty table.
- **Write failure** (permission denied, disk full): Log warning, clean up temp file, do not propagate.
- **Directory check failure during prune**: Treat as non-existent, remove entry.

The file format is machine-managed only. Hand-edits are not supported and may be overwritten by the next persist call.

### File Format

Plain JSON object, one key per worktree. Keys are worktree directory basenames, values are description strings. Written as compact JSON via `vim.json.encode`. Key order is not guaranteed and may change between writes. With the expected 2-5 short entries, this is readable enough for quick reference.

## Scope

### What Changes

- `lua/tw/agent/init.lua`:
  - Add `persist_worktree_description` function (~35 lines).
  - Change `generate_pane_description` signature to accept `cwd` parameter.
  - Add ~5 lines of variable capture before the async call.
  - Add ~3 lines in the `vim.schedule` block to invoke the new function.
- `WorkmuxPrompt()`: Pass `cwd` to `generate_pane_description` (one-line change).

### What Does Not Change

- The tmux `@desc` flow -- unchanged, the file write is additive.
- No new tracked source files or modules. One runtime file (`worktrees.json`) is created outside git repos.
- No new dependencies.

## Validation

- **`make lint`**: Confirms no syntax or style issues.
- **Manual test**: Run a workmux prompt in a feature worktree, verify `worktrees.json` appears in the parent directory with the correct entry. Run again in a different worktree, verify the entry is added. Delete a worktree directory, run again, verify the stale entry is pruned.
- **Edge cases**: Run from the main worktree (should not write). Run with a corrupted `worktrees.json` (should overwrite cleanly). Run with `worktrees.json` not writable (should log warning, not crash).
- **No automated tests are added.** The function uses `vim.json.encode` and `vim.fn.isdirectory` which are Neovim-specific and not available in standalone Lua or the existing Go integration test suite without running a headless Neovim process. The manual validation above is sufficient for this scope.
