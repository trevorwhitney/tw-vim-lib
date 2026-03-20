# Diffview File Path Resolution for AI Agent Context

**Date:** 2026-03-20
**Status:** Approved

## Problem

The AI agent context-sending keymaps (`<leader>c*`, `<leader>cf`, `<leader>cb`) use `vim.fn.expand("%")` to resolve the current buffer's filename. Inside a diffview panel, non-LOCAL buffers have synthetic names like `diffview:///Users/foo/project/.git/abc1234def0/src/bar.lua` instead of real file paths. When this URI is sent to the AI agent via the `@file:line` syntax, the agent cannot read the file because the path does not exist on disk.

The primary use case is `<leader>gd`, which opens a Telescope commit picker and runs `DiffviewOpen <sha>..HEAD`. The right-side panel shows the HEAD/working tree version (LOCAL rev, real file path), while the left side shows the commit version (synthetic URI). When the user is on the right side (HEAD), `expand("%")` already returns the real path. The issue occurs on the left side or in non-HEAD diff comparisons.

## Design Decision

Parse the `diffview://` URI to extract the real file path using string matching. This avoids depending on diffview's internal Lua API and keeps the change minimal.

## Solution

### New utility function

Add `resolve_file_path()` to `lua/tw/agent/util.lua`:

```lua
--- Resolve a buffer name to a real file path.
--- Handles diffview:// URIs by extracting the relative file path.
--- @param bufname string|nil The buffer name (defaults to vim.fn.expand("%"))
--- @return string|nil resolved_path The resolved file path, or nil for null/unresolvable buffers
--- @return boolean is_diffview Whether the path was extracted from a diffview URI
function util.resolve_file_path(bufname)
    bufname = bufname or vim.fn.expand("%")

    -- Not a diffview buffer — return as-is
    if not bufname:match("^diffview://") then
        return bufname, false
    end

    -- Null buffer — no file to reference
    if bufname == "diffview://null" then
        return nil, true
    end

    -- Strip the diffview:// prefix
    local path = bufname:gsub("^diffview://", "")

    -- Find .git/ anchor and extract the portion after .git/<rev>/
    -- Patterns:
    --   Commit: .../.git/<sha-abbrev>/<rel-path>
    --   Stage:  .../.git/:<N>:/<rel-path>
    local rel_path = path:match("%.git/[^/]+/(.+)$") -- commit rev
        or path:match("%.git/:%d+:/(.+)$")           -- stage rev

    if rel_path then
        return rel_path, true
    end

    -- Fallback: return raw bufname if parsing fails
    return bufname, false
end
```

### Affected call sites

All in `lua/tw/agent/init.lua`:

1. **`SendSelection()`** (line ~590): Replace `vim.fn.expand("%")` with `util.resolve_file_path()`. When `nil` is returned (null buffer), warn and return early.

2. **`SendSymbol()`** (line ~610): Same replacement.

3. **`SendFile()`** (line ~622): Same replacement.

4. **`SendOpenBuffers()`** (via `util.get_buffer_files()`): Update `get_buffer_files()` in `util.lua` to call `resolve_file_path()` for each buffer name, skipping nil results (null diffview buffers). Deduplicate paths so the same file isn't sent twice (e.g., if both the real buffer and a diffview buffer for the same file are open).

### Path relativity handling

- **Non-diffview buffers:** `resolve_file_path()` returns the raw `expand("%")` result. Callers continue to use `Path:new(filename):make_relative(git_root)` as before.
- **Diffview buffers:** `resolve_file_path()` returns a path already relative to the repo root (extracted from the URI). Callers should detect this via the `is_diffview` return value and skip the `make_relative()` call, or callers can simply always call `make_relative()` — plenary's `make_relative()` is a no-op when the path is already relative.

### Edge cases

| Scenario | Behavior |
|----------|----------|
| `diffview://null` | Returns `nil`. Callers warn and skip. |
| Right-side LOCAL buffer (HEAD) | Not a diffview URI. Returns real path as-is. Exact line numbers. |
| Left-side commit buffer | Extracts real relative path from URI. Line numbers from the diff view (may differ from current file on disk). |
| Two-commit diff (`sha1..sha2`) | Both sides are diffview URIs. Extracts real path from whichever side the cursor is on. Line numbers may be stale. |
| Stage buffer (`:0:`) | Extracts real relative path. |
| Regular buffer (not in diffview) | Returns path unchanged. |
| URI parsing fails | Falls back to returning the raw buffer name (existing behavior). |

## Scope

This change affects only the agent context-sending functions. It does not modify diffview configuration, keymaps, or any other part of the plugin.

## Files Changed

- `lua/tw/agent/util.lua` — Add `resolve_file_path()` function
- `lua/tw/agent/init.lua` — Update `SendSelection()`, `SendSymbol()`, `SendFile()` to use `resolve_file_path()`
- `lua/tw/agent/util.lua` — Update `get_buffer_files()` to use `resolve_file_path()` and deduplicate
