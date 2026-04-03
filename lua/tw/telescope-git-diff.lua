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
		-- Cap at 500 to keep the picker responsive on large repos
		return { "git", "log", "--oneline", "--max-count=500" }
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
		local sha = line:match("^(%x+)")
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
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	opts = opts or {}
	local no_upstream = not has_upstream()
	local show_all = no_upstream

	-- Capture the current file path BEFORE opening the picker.
	-- Once the picker opens, vim's "%" refers to the Telescope prompt buffer.
	local raw = opts.current_file and vim.fn.expand("%:p") or ""
	local current_file_path = raw ~= "" and raw or nil

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
