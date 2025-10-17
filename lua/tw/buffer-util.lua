local M = {}

-- Determines if a buffer should be auto-saved
-- @param bufnr number|nil Buffer number (defaults to current buffer)
-- @return boolean true if buffer should be auto-saved, false otherwise
function M.should_autosave(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local buf_name = vim.api.nvim_buf_get_name(bufnr)

	-- Early return for empty buffer name
	if buf_name == "" then
		return false
	end

	-- Early return for URI schemes (fugitive://, octo://, dap://, etc.)
	if buf_name:match("://") then
		return false
	end

	-- Early return for special buffer name patterns (e.g., [dap-repl])
	if buf_name:match("^%[.*%]$") then
		return false
	end

	-- Excluded filetypes that should never be auto-saved
	local excluded_filetypes = {
		"aerial",
		"dap-repl",
		"dapui_console",
		"fugitive",
		"help",
		"nofile",
		"NvimTree",
		"qf",
		"quickfix",
		"telescope",
		"terminal",
		"trouble",
		"Trouble",
	}

	local filetype = vim.bo[bufnr].filetype
	if vim.tbl_contains(excluded_filetypes, filetype) then
		return false
	end

	-- Check buffer type (must be normal file buffer)
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" then
		return false
	end

	-- Check if buffer is modifiable
	if not vim.bo[bufnr].modifiable then
		return false
	end

	-- Check if buffer is readonly
	if vim.bo[bufnr].readonly then
		return false
	end

	-- Check if file is writable on disk
	local expanded = vim.fn.expand(buf_name)
	if vim.fn.filewritable(expanded) ~= 1 then
		return false
	end

	return true
end

return M
