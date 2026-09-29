local util = require("tw.telescope-git-branch-diff.util")

local M = {}

function M.git_branch_diff_picker(opts)
	opts = opts or {}
	-- Capture the file before Telescope replaces the current buffer.
	local current_file_path
	if opts.current_file then
		current_file_path = vim.fn.expand("%:p")
		if vim.bo.buftype ~= "" or current_file_path == "" then
			vim.notify("Open a file to diff against a branch", vim.log.levels.WARN)
			return
		end
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = opts.current_file and "Diff Current File Against Branch" or "Diff Against Branch",
			finder = finders.new_oneshot_job(util.git_branch_cmd(), {
				entry_maker = util.make_entry_maker(),
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end

					actions.close(prompt_bufnr)

					local cmd = util.build_diff_command(entry.value, current_file_path, vim.fn.fnameescape)
					if cmd then
						vim.cmd(cmd)
					end
				end)

				return true
			end,
		})
		:find()
end

return M
