local Path = require("plenary.path")

local M = {}

-- adapted from https://github.com/greggh/claude-code.nvim/blob/main/lua/claude-code/git.lua
function M.get_git_root()
	-- Check if we're in a git repository
	local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
	if not handle then
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	-- Strip trailing whitespace and newlines for reliable matching
	result = result:gsub("[\n\r%s]*$", "")

	if result == "true" then
		-- Get the git root path
		local root_handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
		if not root_handle then
			return nil
		end

		local git_root = root_handle:read("*a")
		root_handle:close()

		-- Remove trailing whitespace and newlines
		git_root = git_root:gsub("[\n\r%s]*$", "")

		return git_root
	end

	return nil
end

function M.get_buffer_files()
	local files = {}
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		-- Include all buffers that are listed (which includes bufferline tabs)
		if vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			-- Check if buffer has a valid file path and exists on disk
			if name ~= "" and vim.fn.filereadable(name) == 1 then
				local rel_path = Path:new(name):make_relative(M.get_git_root())
				table.insert(files, "@" .. rel_path)
			end
		end
	end

	return files
end

return M
