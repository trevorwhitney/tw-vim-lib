# Telescope Git Diff Picker

## Problem

Reviewing a batch of commits (typically unpushed work from an agentic coding session) requires manually typing commit SHAs into `vim.fn.input()`. There is no way to visually browse the log and select a commit range for diffview.

## Solution

Replace the `<leader>gd` and `<leader>gD` keybindings with a Telescope picker that shows `git log --oneline`. The user can select one or two commits, and the picker opens `DiffviewOpen` with the appropriate range.

## User Workflow

1. Press `<leader>gd` (all files) or `<leader>gD` (current file).
2. Telescope opens showing unpushed commits (short SHA + message title).
3. Navigate to a commit and either:
   - Press `<CR>` directly to diff that commit against HEAD.
   - Press `<Tab>` to mark it, navigate to a second commit, press `<Tab>`, then `<CR>` to diff the range.
4. Diffview opens with the selected range.

### Toggling Commit Scope

- **Default:** unpushed commits only (`git log --oneline @{upstream}..HEAD`).
- **`<C-u>` toggle:** switches between unpushed and all commits. The picker title updates to reflect the current mode ("Diff (unpushed)" vs "Diff (all)"). Results refresh in-place without closing the picker.
- **No upstream fallback:** if no upstream branch is set, default to all commits. Title shows "Diff (all -- no upstream)".

## Selection Behavior

| Selection | Command |
|-----------|---------|
| 0 (just `<CR>` on highlighted entry) | `DiffviewOpen <commit>..HEAD` |
| 1 (one `<Tab>` + `<CR>`) | `DiffviewOpen <commit>..HEAD` |
| 2 (two `<Tab>` + `<CR>`) | Auto-sort older first: `DiffviewOpen <older>..<newer>` |
| 3+ | Notify user: "Select at most 2 commits" — no action |

For `<leader>gD`, append ` -- %` to the command (scopes diff to current file).

## Architecture

### New Module: `lua/tw/telescope-git-diff.lua`

Single new file containing the picker logic. Exposes two public functions:

```lua
local M = {}

--- Open the git diff telescope picker (all files).
function M.git_diff_picker() end

--- Open the git diff telescope picker scoped to the current file.
function M.git_diff_picker_current_file() end

return M
```

Both functions call a shared internal `create_picker(opts)` where `opts.current_file` controls the `-- %` suffix.

### Internal Design

**Finder:** uses `telescope.finders.new_oneshot_job` (or `new_async_job`) to run `git log --oneline`. The command changes based on the current mode:
- Unpushed: `{ "git", "log", "--oneline", "@{upstream}..HEAD" }`
- All: `{ "git", "log", "--oneline" }`

**Upstream detection:** before opening the picker, run `git rev-parse --abbrev-ref @{upstream}` to check if an upstream exists. If it fails, set mode to "all" and flag `no_upstream = true`.

**`<C-u>` toggle:** swaps the finder on the live picker instance via `picker:refresh(new_finder, { reset_prompt = true })` and updates the prompt title.

**Entry parsing:** each line from `git log --oneline` is `<sha> <message>`. The entry maker splits on the first space to extract the SHA for use in the DiffviewOpen command. The full line is displayed to the user.

**Commit sorting:** when two commits are selected, determine chronological order by comparing their position in the git log output (earlier in the log = newer). The commit that appears later in the list is older. This avoids an extra `git log` call.

**Action on `<CR>`:**
1. Collect multi-selections. If empty, use the current highlighted entry.
2. Validate count (1 or 2, otherwise notify and return).
3. Build the DiffviewOpen command string.
4. Close the picker.
5. Run `vim.cmd("DiffviewOpen " .. range)`.

### Modified: `lua/tw/git.lua`

Replace the two `vim.fn.input()`-based keybinding functions (lines 90-108) with calls to the new module:

```lua
-- Before (lines 90-98):
{
    "<leader>gd",
    function()
        local commit = vim.fn.input("[Commit] > ")
        vim.cmd("DiffviewOpen " .. commit)
    end,
    desc = "Diff Split (Against Commit)",
},

-- After:
{
    "<leader>gd",
    function()
        require("tw.telescope-git-diff").git_diff_picker()
    end,
    desc = "Diff (Commit Picker)",
},
```

Same pattern for `<leader>gD` calling `git_diff_picker_current_file()`.

### No Other File Changes

`lua/tw/telescope.lua` is not modified. The new module requires telescope APIs directly, consistent with how other parts of the codebase use telescope (e.g., `lua/tw/lsp.lua` requiring `telescope.builtin`).

## Picker Mappings Summary

| Key | Mode | Action |
|-----|------|--------|
| `<Tab>` | insert/normal | Toggle multi-select on current entry, move down |
| `<S-Tab>` | insert/normal | Toggle multi-select on current entry, move up |
| `<CR>` | insert/normal | Confirm selection, open DiffviewOpen |
| `<C-u>` | insert/normal | Toggle unpushed/all commits, refresh results |
| `<Esc>` / `<C-c>` | insert/normal | Cancel (standard Telescope behavior) |

## Edge Cases

- **No upstream branch:** fall back to all commits, title indicates "no upstream".
- **No commits at all:** empty picker, user can cancel. No special handling needed.
- **No unpushed commits:** empty picker in unpushed mode. User can `<C-u>` to switch to all. Title shows "Diff (unpushed)" with an empty list, which is self-explanatory.
- **3+ selections:** notify with `vim.notify("Select at most 2 commits", vim.log.levels.WARN)`, do nothing.
- **Detached HEAD:** `@{upstream}` will fail, same as no-upstream fallback.

## Dependencies

- `telescope.nvim` (already installed)
- `diffview.nvim` (already installed)
- No new plugin dependencies.
