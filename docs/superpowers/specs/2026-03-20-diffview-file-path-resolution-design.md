# Diffview File Path Resolution for AI Agent Context

**Date:** 2026-03-20
**Status:** Approved

## Problem

The AI agent context-sending keymaps (`<leader>c*`, `<leader>cf`, `<leader>cb`) use `vim.fn.expand("%")` to resolve the current buffer's filename. Inside a diffview panel, non-LOCAL buffers have synthetic names like `diffview:///Users/foo/project/.git/abc1234def0/src/bar.lua` instead of real file paths. When this URI is sent to the AI agent via the `@file:line` syntax, the agent cannot read the file because the path does not exist on disk.

The primary use case is `<leader>gd`, which opens a Telescope commit picker and runs `DiffviewOpen <sha>..HEAD`. The right-side panel shows the HEAD/working tree version (LOCAL rev, real file path), while the left side shows the commit version (synthetic URI). When the user is on the right side (HEAD), `expand("%")` already returns the real path. The issue occurs on the left side or in non-HEAD diff comparisons.

## Design Decision

Parse the `diffview://` URI to extract the real file path using string matching. This creates a coupling to diffview's URI format (not its Lua API). The URI format is generated in `diffview.nvim/lua/diffview/vcs/file.lua` (`File:create_buffer()`) and has been stable across versions. The trade-off is accepted: the alternative (using diffview's internal Lua API) creates a heavier, less documented dependency. If diffview changes its URI format, our parsing returns `nil` and the user sees a warning — a safe failure mode.

### Stale line numbers

When the cursor is in a non-HEAD diffview buffer (left side of `sha..HEAD`, or either side of `sha1..sha2`), the line numbers from the diff view may not match the current file on disk. This is a conscious, accepted trade-off:

- The primary use case (right side = HEAD) always has accurate line numbers.
- For non-HEAD buffers, stale line numbers still provide useful approximate context to the agent.
- The `@file:line` syntax is the only mechanism available; sending buffer content is a separate feature.
- The agent can handle slightly off line numbers better than it can handle a `diffview://` URI.

## Solution

### New utility function

Add `resolve_file_path()` to `lua/tw/agent/util.lua`. This function is **side-effect free** — no notifications, no writes, no state mutation. When called with an explicit `bufname` argument, it is a pure function suitable for unit testing. The default argument (`vim.fn.expand("%")`) reads vim state for caller convenience.

The function returns both the resolved absolute path and the repo root, so callers can use the correct root for `make_relative()` regardless of Neovim's CWD.

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
function util.resolve_file_path(bufname)
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
    -- The rev token is always a single path component (sha abbreviation
    -- or :N: stage indicator). Branch names with slashes do not appear
    -- because diffview abbreviates commit hashes, not ref names.
    --
    -- The repo root is extracted from the URI itself (the portion before
    -- .git/) rather than using CWD-based git commands, ensuring correct
    -- resolution even when Neovim's CWD differs from the repo root.
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
        -- Parse failure — return nil, let caller handle
        return nil, nil
    end

    return repo_root .. "/" .. rel_path, repo_root
end
```

### Affected call sites

All in `lua/tw/agent/init.lua`:

1. **`SendSelection()`**: Revised operation order:
   ```
   1. Call util.resolve_file_path() — if nil, warn and return (no side effects)
   2. Yank selection (normal! "sy) — this sets the '< and '> marks
   3. Read visual selection marks (vim.fn.line("'<"), vim.fn.line("'>"))
   4. Escape visual mode (normal! <Esc>)
   5. Build reference and send
   ```
   Path resolution happens **before** the yank so that a nil result causes an early return with no yank or mode-change side effects. The yank still happens before reading marks because `'<`/`'>` marks are set reliably by the yank command.

2. **`SendSymbol()`**: Replace `vim.fn.expand("%")` with `util.resolve_file_path()`. If `nil`, warn and return early.

3. **`SendFile()`**: Same replacement pattern.

4. **`get_buffer_files()` in `util.lua`**: Revised flow:
   ```
   for each listed buffer:
     1. Get raw buffer name via nvim_buf_get_name()
     2. Call resolve_file_path(raw_name) — skip if nil
     3. Call filereadable(resolved_path) — skip if not readable
     4. Convert to relative using repo_root (if returned) or get_git_root()
     5. Add to seen set (keyed by absolute path) to deduplicate
     6. If not already seen, add "@" .. rel_path to output list
   ```
   Key: `resolve_file_path()` is called **before** `filereadable()`, so diffview URIs are resolved to real paths before the readability check.

### Path handling contract

`resolve_file_path()` returns `(absolute_path, repo_root)` or `(nil, nil)`:

- **`absolute_path`**: Always an absolute file path. Never relative, empty, or a `diffview://` URI.
- **`repo_root`**: The git repo root extracted from the diffview URI, or `nil` for non-diffview buffers. When `repo_root` is `nil`, callers fall back to `util.get_git_root()` (CWD-based) for the `make_relative()` call.

This ensures CWD-independent path resolution for diffview buffers while maintaining backward compatibility for regular buffers.

Call site pattern:
```lua
local filename, repo_root = util.resolve_file_path()  -- was: vim.fn.expand("%")
if not filename then
    vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
    return
end
local git_root = repo_root or util.get_git_root()
local rel_path = Path:new(filename):make_relative(git_root)
```

### Edge cases

| Scenario | Behavior |
|----------|----------|
| `diffview://null` | Returns `(nil, nil)`. Callers warn and skip. |
| Right-side LOCAL buffer (HEAD) | Not a diffview URI. Returns `(real_path, nil)`. Line numbers are exact. |
| Left-side commit buffer | Extracts path from URI, resolves to absolute using repo root from URI. Returns `(abs_path, repo_root)`. Line numbers from diff view (may differ from disk — accepted trade-off). |
| Two-commit diff (`sha1..sha2`) | Both sides are diffview URIs. Extracts and resolves path. Line numbers may be stale. |
| Stage buffer (`:0:`) | Extracts path from URI, resolves to absolute. Returns `(abs_path, repo_root)`. |
| Regular buffer (not in diffview) | Returns `(path, nil)` unchanged (already absolute). |
| Empty buffer name (`""`) | Returns `(nil, nil)`. Callers warn and skip. |
| URI parsing fails | Returns `(nil, nil)`. Callers warn and skip. |
| Deleted/renamed file (path in diff no longer exists on disk) | Returns the resolved absolute path. `filereadable()` in `get_buffer_files()` filters it out. For `SendSelection`/`SendSymbol`/`SendFile`, the path is sent — the agent receives it and reports the file doesn't exist, which is acceptable. |
| Git worktrees/submodules | Untested. If diffview generates a different URI structure, parsing returns `(nil, nil)` and callers warn — safe failure mode. |
| `DiffviewFileHistory` buffers | Expected to use the same URI format as `DiffviewOpen`. If format differs, parsing returns `(nil, nil)` — safe failure mode. |
| Duplicate buffers (diffview + real buffer for same file) | Both resolve to the same absolute path. `get_buffer_files()` deduplicates so the file appears once. |

### User notification

Notification is the **caller's** responsibility, not the resolver's. When `resolve_file_path()` returns `nil`, callers display:
```
Cannot resolve file path in this buffer
```
at `vim.log.levels.WARN`. There is exactly one notification per failure — no duplication.

## Scope

This change affects only the agent context-sending functions. It does not modify diffview configuration, keymaps, or any other part of the plugin. Other synthetic URI schemes (e.g., `fugitive://`) continue to be filtered by the existing `filereadable()` check in `get_buffer_files()` and are out of scope.

## Files Changed

- `lua/tw/agent/util.lua` — Add `resolve_file_path()` function, update `get_buffer_files()` with dedup
- `lua/tw/agent/init.lua` — Update `SendSelection()`, `SendSymbol()`, `SendFile()` to use `resolve_file_path()`

## Validation

| Test scenario | Input | Expected output |
|---------------|-------|-----------------|
| Regular buffer | `/Users/foo/project/src/bar.lua` | `(/Users/foo/project/src/bar.lua, nil)` |
| Commit diffview buffer | `diffview:///Users/foo/project/.git/abc1234def0/src/bar.lua` | `(/Users/foo/project/src/bar.lua, /Users/foo/project)` |
| Stage diffview buffer | `diffview:///Users/foo/project/.git/:0:/src/bar.lua` | `(/Users/foo/project/src/bar.lua, /Users/foo/project)` |
| Null diffview buffer | `diffview://null` | `(nil, nil)` |
| Malformed diffview URI | `diffview://something-unexpected` | `(nil, nil)` |
| Empty buffer name | `""` | `(nil, nil)` |
| `.git` in parent dir | `diffview:///Users/foo/.git-projects/repo/.git/abc123/src/bar.lua` | `(/Users/foo/.git-projects/repo/src/bar.lua, /Users/foo/.git-projects/repo)` |
| `nil` buffer name | `nil` | Result of `expand("%")` through same logic |
