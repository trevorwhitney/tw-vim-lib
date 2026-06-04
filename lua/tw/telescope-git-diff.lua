local util = require("tw.telescope-git-diff.util")

local M = {}

--- Create and open the git diff telescope picker.
--- @param opts { current_file: boolean }
local function create_picker(opts)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	opts = opts or {}
	local no_upstream = not util.has_upstream()
	local show_all = no_upstream

	-- Capture the current file path BEFORE opening the picker.
	-- Once the picker opens, vim's "%" refers to the Telescope prompt buffer.
	local raw = opts.current_file and vim.fn.expand("%:p") or ""
	local current_file_path = raw ~= "" and raw or nil

	local index_counter = { n = 0 }

	local function make_finder(is_all)
		index_counter.n = 0
		return finders.new_oneshot_job(util.git_log_cmd(is_all), {
			entry_maker = util.make_entry_maker(index_counter),
		})
	end

	pickers
		.new({}, {
			prompt_title = util.picker_title(show_all, no_upstream),
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

					local cmd = util.build_diff_command(selections, current_file_path, vim.fn.fnameescape)

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
						picker.prompt_border:change_title(util.picker_title(show_all, no_upstream))
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
