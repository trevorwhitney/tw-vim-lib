# Telescope Git Diff Picker Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `<leader>gd` and `<leader>gD` with a Telescope picker for selecting one or two commits and opening DiffviewOpen with the appropriate range.

**Architecture:** A single new Lua module (`lua/tw/telescope-git-diff.lua`) contains all picker logic. It exposes two public functions (`git_diff_picker` and `git_diff_picker_current_file`) that share a common internal `create_picker(opts)`. The existing keybindings in `lua/tw/git.lua` are updated to call these functions instead of using `vim.fn.input()`.

**Tech Stack:** Neovim Lua, telescope.nvim (pickers, finders, actions, action_state), diffview.nvim

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lua/tw/telescope-git-diff.lua` | Create | All picker logic: finder creation, upstream detection, entry parsing, commit sorting, `<C-o>` toggle, DiffviewOpen command building |
| `lua/tw/git.lua` | Modify (lines 89-108) | Replace `vim.fn.input()` keybinding functions with calls to new module |

---

### Task 1: Create the picker module skeleton with upstream detection

**Files:**
- Create: `lua/tw/telescope-git-diff.lua`

- [ ] **Step 1: Create the module file with requires and public API**

Create `lua/tw/telescope-git-diff.lua` with the module skeleton, imports, and the two public functions that delegate to a shared `create_picker`:

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

--- Create and open the git diff telescope picker.
--- @param opts { current_file: boolean }
local function create_picker(opts)
    -- placeholder: will be implemented in subsequent tasks
end

function M.git_diff_picker()
    create_picker({ current_file = false })
end

function M.git_diff_picker_current_file()
    create_picker({ current_file = true })
end

return M
```

- [ ] **Step 2: Verify the module loads without errors**

Open Neovim and run:
```
:lua require("tw.telescope-git-diff")
```
Expected: no errors. The module loads and returns the table.

- [ ] **Step 3: Commit**

```bash
git add lua/tw/telescope-git-diff.lua
git commit -m "feat: add telescope-git-diff module skeleton with upstream detection"
```

---

### Task 2: Implement the core picker with entry parsing and single-commit action

**Files:**
- Modify: `lua/tw/telescope-git-diff.lua`

- [ ] **Step 1: Implement the entry maker**

Add an `entry_maker` function after the `picker_title` function. Each `git log --oneline` line is `<sha> <message>`. The entry stores the SHA as `value`, the full line as `display`, the full line as `ordinal` (for filtering), and the entry's index for sorting:

```lua
--- Parse a git log --oneline line into a telescope entry.
--- @param index number The position in the log (1 = newest)
--- @return fun(line: string): table
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
```

- [ ] **Step 2: Implement `create_picker` with finder and single-commit action**

Replace the `create_picker` placeholder with the full implementation. This handles upstream detection, creates the finder and picker, and implements the `<CR>` action for single-commit selection (diff against HEAD):

```lua
local function create_picker(opts)
    opts = opts or {}
    local no_upstream = not has_upstream()
    local show_all = no_upstream

    local index_counter = { n = 0 }

    local function make_finder(is_all)
        index_counter.n = 0
        return finders.new_oneshot_job(git_log_cmd(is_all), {
            entry_maker = make_entry_maker(index_counter),
        })
    end

    local current_finder = make_finder(show_all)

    pickers
        .new({}, {
            prompt_title = picker_title(show_all, no_upstream),
            finder = current_finder,
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

                    if opts.current_file then
                        cmd = cmd .. " -- %"
                    end

                    vim.cmd(cmd)
                end)

                return true
            end,
        })
        :find()
end
```

- [ ] **Step 3: Smoke test the picker**

Open Neovim in this repo and run:
```
:lua require("tw.telescope-git-diff").git_diff_picker()
```
Expected: Telescope opens showing commits. Pressing `<CR>` on a commit opens DiffviewOpen with `<sha>..HEAD`. Close diffview with `:DiffviewClose`.

- [ ] **Step 4: Test multi-select**

Open the picker again. Press `<Tab>` on one commit, navigate to another, press `<Tab>`, then `<CR>`.
Expected: DiffviewOpen opens with `<older>..<newer>` range showing the changes between those two commits.

- [ ] **Step 5: Test current file variant**

Open Neovim on a file with changes across commits and run:
```
:lua require("tw.telescope-git-diff").git_diff_picker_current_file()
```
Expected: same picker, but DiffviewOpen command ends with ` -- %`, scoping to the current file.

- [ ] **Step 6: Commit**

```bash
git add lua/tw/telescope-git-diff.lua
git commit -m "feat: implement core git diff picker with entry parsing and commit selection"
```

---

### Task 3: Implement the `<C-o>` toggle between unpushed and all commits

**Files:**
- Modify: `lua/tw/telescope-git-diff.lua`

- [ ] **Step 1: Add the `<C-o>` mapping inside `attach_mappings`**

In the `attach_mappings` function, after the `actions.select_default:replace(...)` block and before `return true`, add the `<C-o>` mapping for both insert and normal mode. This toggles the `show_all` state, rebuilds the finder, refreshes the picker, and updates the title:

```lua
                map({ "i", "n" }, "<C-o>", function()
                    show_all = not show_all
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    picker:refresh(make_finder(show_all), { reset_prompt = true })
                    picker.prompt_border:change_title(picker_title(show_all, no_upstream))
                end, { desc = "Toggle unpushed/all commits" })
```

Note: when `no_upstream` is true, `show_all` starts as `true`. Toggling it to `false` would attempt to show unpushed commits which would fail. Guard against this:

```lua
                map({ "i", "n" }, "<C-o>", function()
                    if no_upstream then
                        vim.notify("No upstream branch set — showing all commits", vim.log.levels.INFO)
                        return
                    end
                    show_all = not show_all
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    picker:refresh(make_finder(show_all), { reset_prompt = true })
                    picker.prompt_border:change_title(picker_title(show_all, no_upstream))
                end, { desc = "Toggle unpushed/all commits" })
```

- [ ] **Step 2: Smoke test the toggle**

Open the picker in a repo with an upstream branch:
```
:lua require("tw.telescope-git-diff").git_diff_picker()
```
Expected: shows unpushed commits, title says "Diff (unpushed)". Press `<C-o>`: list refreshes to show all commits, title changes to "Diff (all)". Press `<C-o>` again: back to unpushed.

- [ ] **Step 3: Test the no-upstream fallback**

Create a new local branch with no upstream and open the picker:
```
:lua require("tw.telescope-git-diff").git_diff_picker()
```
Expected: shows all commits, title says "Diff (all -- no upstream)". Press `<C-o>`: notification says "No upstream branch set — showing all commits", list does not change.

- [ ] **Step 4: Commit**

```bash
git add lua/tw/telescope-git-diff.lua
git commit -m "feat: add <C-o> toggle between unpushed and all commits in git diff picker"
```

---

### Task 4: Wire up keybindings in git.lua

**Files:**
- Modify: `lua/tw/git.lua:89-108`

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

- [ ] **Step 3: Run lint**

```bash
make lint
```
Expected: no errors from `luacheck` for the new or modified files.

- [ ] **Step 4: Smoke test both keybindings**

Open Neovim and test:
1. Press `<leader>gd` — picker opens, select a commit, DiffviewOpen shows full repo diff.
2. `:DiffviewClose`
3. Press `<leader>gD` — picker opens, select a commit, DiffviewOpen shows diff for current file only.

- [ ] **Step 5: Commit**

```bash
git add lua/tw/git.lua
git commit -m "feat: wire <leader>gd and <leader>gD to telescope git diff picker"
```

---

### Task 5: Clean up dead code

**Files:**
- Modify: `lua/tw/git.lua:275-277`

- [ ] **Step 1: Remove the old `M.diffSplit` function**

The function `M.diffSplit` at `lua/tw/git.lua:275-277` is no longer referenced anywhere — it was the old programmatic entry point. Remove it:

```lua
-- Remove these lines (275-277):
function M.diffSplit(commit)
	vim.cmd("DiffViewOpen " .. commit)
end
```

- [ ] **Step 2: Verify no other references to `diffSplit`**

Search the codebase for `diffSplit`:
```bash
grep -r "diffSplit" lua/
```
Expected: no results.

- [ ] **Step 3: Run lint**

```bash
make lint
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lua/tw/git.lua
git commit -m "chore: remove unused M.diffSplit function"
```

---

### Task 6: End-to-end validation

- [ ] **Step 1: Full workflow test — single commit, all files**

1. Open Neovim in a git repo with an upstream branch.
2. Press `<leader>gd`.
3. Picker opens showing unpushed commits with title "Diff (unpushed)".
4. Navigate to a commit, press `<CR>`.
5. DiffviewOpen shows diff of `<commit>..HEAD` for all files.
6. `:DiffviewClose`.

- [ ] **Step 2: Full workflow test — two commits, all files**

1. Press `<leader>gd`.
2. Press `<C-o>` to switch to all commits. Title changes to "Diff (all)".
3. `<Tab>` on an older commit, navigate to a newer commit, `<Tab>`, `<CR>`.
4. DiffviewOpen shows diff between the two commits for all files.
5. `:DiffviewClose`.

- [ ] **Step 3: Full workflow test — single commit, current file**

1. Open a file that has been modified across commits.
2. Press `<leader>gD`.
3. Select a commit, press `<CR>`.
4. DiffviewOpen shows diff for the current file only.
5. `:DiffviewClose`.

- [ ] **Step 4: Edge case — 3+ selections**

1. Press `<leader>gd`, toggle to all commits.
2. `<Tab>` three commits, press `<CR>`.
3. Expected: warning notification "Select at most 2 commits", no DiffviewOpen.

- [ ] **Step 5: Edge case — empty unpushed list**

1. Push all local commits so there are none unpushed.
2. Press `<leader>gd`.
3. Expected: empty picker with title "Diff (unpushed)".
4. Press `<C-o>` — switches to all commits, list populates.

- [ ] **Step 6: Run final lint**

```bash
make lint
```
Expected: clean.
