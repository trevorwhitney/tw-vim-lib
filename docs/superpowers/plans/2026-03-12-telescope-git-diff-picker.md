# Telescope Git Diff Picker Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `<leader>gd` and `<leader>gD` with a Telescope picker for selecting one or two commits and opening DiffviewOpen with the appropriate range, with a `<C-o>` toggle between unpushed and all commits.

**Architecture:** A single new Lua module (`lua/tw/telescope-git-diff.lua`) contains all picker logic. It exposes two public functions (`git_diff_picker` and `git_diff_picker_current_file`) that share a common internal `create_picker(opts)`. The existing keybindings in `lua/tw/git.lua` are updated to call these functions instead of using `vim.fn.input()`.

**Tech Stack:** Neovim Lua, telescope.nvim (pickers, finders, actions, action_state), diffview.nvim

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lua/tw/telescope-git-diff.lua` | Create | All picker logic: finder creation, upstream detection, entry parsing, commit sorting, `<C-o>` toggle, DiffviewOpen command building |
| `lua/tw/git.lua` | Modify (lines 89-108, 275-277) | Replace `vim.fn.input()` keybinding functions with calls to new module; remove unused `M.diffSplit` |

---

### Task 1: Create the complete picker module

**Files:**
- Create: `lua/tw/telescope-git-diff.lua`

- [ ] **Step 1: Create the full module file**

Create `lua/tw/telescope-git-diff.lua` with all helpers, the complete `create_picker` implementation, `<C-o>` toggle, and both public functions.

**Important correctness note:** The `current_file` path must be captured via `vim.fn.expand("%:p")` *before* opening the picker. When the picker is open, `%` refers to the Telescope prompt buffer, not the user's file. Store the resolved path and use it in the DiffviewOpen command instead of relying on `%` expansion after close.

**Important feasibility note:** `picker.prompt_border:change_title()` is not a stable Telescope API. Guard the call with `pcall` or a nil check so the toggle still works even if the internal path changes in a future Telescope update.

```lua
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}

--- Check if an upstream branch exists for the current branch.
--- @return boolean
local function has_upstream()
    local result = vim.fn.systemlist("git rev-parse --abbrev-ref @{upstream} 2>/dev/null")
    return vim.v.shell_error == 0 and #result > 0 and result[1] ~= ""
end

--- Build the git log command for the given mode.
--- @param show_all boolean Whether to show all commits or just unpushed
--- @return string[]
local function git_log_cmd(show_all)
    if show_all then
        return { "git", "log", "--oneline" }
    else
        return { "git", "log", "--oneline", "@{upstream}..HEAD" }
    end
end

--- Build the prompt title for the current picker state.
--- @param show_all boolean
--- @param no_upstream boolean
--- @return string
local function picker_title(show_all, no_upstream)
    if no_upstream then
        return "Diff (all -- no upstream)"
    elseif show_all then
        return "Diff (all)"
    else
        return "Diff (unpushed)"
    end
end

--- Parse a git log --oneline line into a telescope entry.
--- Each entry tracks its position in the log for chronological sorting.
--- @param index_counter { n: number } Mutable counter shared across entries
--- @return fun(line: string): table|nil
local function make_entry_maker(index_counter)
    return function(line)
        local sha, message = line:match("^(%S+)%s+(.+)$")
        if not sha then
            return nil
        end
        index_counter.n = index_counter.n + 1
        return {
            value = sha,
            display = line,
            ordinal = line,
            index = index_counter.n,
        }
    end
end

--- Create and open the git diff telescope picker.
--- @param opts { current_file: boolean }
local function create_picker(opts)
    opts = opts or {}
    local no_upstream = not has_upstream()
    local show_all = no_upstream

    -- Capture the current file path BEFORE opening the picker.
    -- Once the picker opens, vim's "%" refers to the Telescope prompt buffer.
    local current_file_path = opts.current_file and vim.fn.expand("%:p") or nil

    local index_counter = { n = 0 }

    local function make_finder(is_all)
        index_counter.n = 0
        return finders.new_oneshot_job(git_log_cmd(is_all), {
            entry_maker = make_entry_maker(index_counter),
        })
    end

    pickers
        .new({}, {
            prompt_title = picker_title(show_all, no_upstream),
            finder = make_finder(show_all),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    local multi = picker:get_multi_selection()
                    local selections = {}

                    if #multi > 0 then
                        for _, entry in ipairs(multi) do
                            table.insert(selections, entry)
                        end
                    else
                        local entry = action_state.get_selected_entry()
                        if entry then
                            table.insert(selections, entry)
                        end
                    end

                    if #selections == 0 then
                        return
                    end

                    if #selections > 2 then
                        vim.notify("Select at most 2 commits", vim.log.levels.WARN)
                        return
                    end

                    actions.close(prompt_bufnr)

                    local cmd
                    if #selections == 1 then
                        cmd = "DiffviewOpen " .. selections[1].value .. "..HEAD"
                    else
                        -- Sort by index: higher index = older (further down the log)
                        table.sort(selections, function(a, b)
                            return a.index > b.index
                        end)
                        local older = selections[1].value
                        local newer = selections[2].value
                        cmd = "DiffviewOpen " .. older .. ".." .. newer
                    end

                    if current_file_path then
                        cmd = cmd .. " -- " .. vim.fn.fnameescape(current_file_path)
                    end

                    vim.cmd(cmd)
                end)

                -- Toggle between unpushed and all commits
                map({ "i", "n" }, "<C-o>", function()
                    if no_upstream then
                        vim.notify("No upstream branch set — showing all commits", vim.log.levels.INFO)
                        return
                    end
                    show_all = not show_all
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    picker:refresh(make_finder(show_all), { reset_prompt = true })
                    -- Update title if the API is available (internal Telescope path)
                    pcall(function()
                        picker.prompt_border:change_title(picker_title(show_all, no_upstream))
                    end)
                end, { desc = "Toggle unpushed/all commits" })

                return true
            end,
        })
        :find()
end

function M.git_diff_picker()
    create_picker({ current_file = false })
end

function M.git_diff_picker_current_file()
    create_picker({ current_file = true })
end

return M
```

- [ ] **Step 2: Verify the module loads and the picker opens**

Open Neovim in this repo and run:
```
:lua require("tw.telescope-git-diff").git_diff_picker()
```
Expected: Telescope opens showing commits. Verify:
1. Pressing `<CR>` on a commit opens `DiffviewOpen <sha>..HEAD`. Close with `:DiffviewClose`.
2. `<Tab>` two commits, `<CR>` opens `DiffviewOpen <older>..<newer>`. Close with `:DiffviewClose`.
3. `<Tab>` three commits, `<CR>` shows warning "Select at most 2 commits", no DiffviewOpen.
4. `<C-o>` toggles between unpushed/all commits with title update.

- [ ] **Step 3: Test the current file variant**

Open a file that has changes across commits and run:
```
:lua require("tw.telescope-git-diff").git_diff_picker_current_file()
```
Expected: same picker, but DiffviewOpen scopes to the current file.

- [ ] **Step 4: Format and commit**

```bash
make format && make lint
git add lua/tw/telescope-git-diff.lua
git commit -m "feat: add telescope git diff picker with commit selection and <C-o> toggle"
```

---

### Task 2: Wire up keybindings and remove dead code in git.lua

**Files:**
- Modify: `lua/tw/git.lua:89-108` (keybindings), `lua/tw/git.lua:275-277` (dead code)

- [ ] **Step 1: Replace the `<leader>gd` keybinding**

In `lua/tw/git.lua`, replace lines 89-98 (the `<leader>gd` entry in the keymap table):

```lua
-- Old (lines 89-98):
			{
				"<leader>gd",
				function()
					local commit = vim.fn.input("[Commit] > ")
					vim.cmd("DiffviewOpen " .. commit)
				end,
				desc = "Diff Split (Against Commit)",
				nowait = false,
				remap = false,
			},

-- New:
			{
				"<leader>gd",
				function()
					require("tw.telescope-git-diff").git_diff_picker()
				end,
				desc = "Diff (Commit Picker)",
				nowait = false,
				remap = false,
			},
```

- [ ] **Step 2: Replace the `<leader>gD` keybinding**

In `lua/tw/git.lua`, replace lines 99-108 (the `<leader>gD` entry):

```lua
-- Old (lines 99-108):
			{
				"<leader>gD",
				function()
					local commit = vim.fn.input("[Commit] > ")
					vim.cmd("DiffviewOpen " .. commit .. " -- %")
				end,
				desc = "Diff Split (Against Commit)",
				nowait = false,
				remap = false,
			},

-- New:
			{
				"<leader>gD",
				function()
					require("tw.telescope-git-diff").git_diff_picker_current_file()
				end,
				desc = "Diff Current File (Commit Picker)",
				nowait = false,
				remap = false,
			},
```

- [ ] **Step 3: Remove the unused `M.diffSplit` function**

Remove the `M.diffSplit` function at `lua/tw/git.lua:275-277` — it is no longer referenced anywhere:

```lua
-- Remove these lines (275-277):
function M.diffSplit(commit)
	vim.cmd("DiffViewOpen " .. commit)
end
```

Verify no other references exist: search for `diffSplit` across the codebase. Expected: no results.

- [ ] **Step 4: Smoke test both keybindings**

Open Neovim and test:
1. Press `<leader>gd` — picker opens, select a commit, DiffviewOpen shows full repo diff. `:DiffviewClose`.
2. Press `<leader>gD` — picker opens, select a commit, DiffviewOpen shows diff for current file only. `:DiffviewClose`.

- [ ] **Step 5: Format, lint, and commit**

```bash
make format && make lint
git add lua/tw/git.lua
git commit -m "feat: wire <leader>gd and <leader>gD to telescope git diff picker"
```
