local M = {}
local api = vim.api

local function set_of(list)
	local set = {}
	for i = 1, #list do
		set[list[i]] = true
	end
	return set
end

local function not_in(var, arr)
	if set_of(arr)[var] == nil then
		return true
	end
end

local function autosave()
	local group = api.nvim_create_augroup("Autosave", {
		clear = true,
	})

	api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
		pattern = "*",
		callback = function(event)
			local buf = event.buf
			local fn = vim.fn
			local skip_fts = {
				"dapui_console",
				"dap-repl",
				"fugitive",
				"Trouble",
			}

			local is_modifiable = fn.getbufvar(buf, "&modifiable") == 1
			local buf_name = fn.bufname(buf)

			if buf_name == "" then
				return
			end

			local name_re = vim.regex("^(fugitive|octo|\\[dap.*):?.*")
			if name_re:match_str(buf_name) then
				return
			end

			local dap_name_re = vim.regex("^\\[dap-repl.*\\]$")
			if dap_name_re:match_str(buf_name) then
				return
			end

			local is_writable = fn.filewritable(fn.expand(buf_name)) == 1
			local is_normal_buffer = fn.getbufvar(buf, "&buftype") == ""

			local ft = fn.getbufvar(buf, "&filetype")
			local is_savable_ft = not_in(ft, skip_fts)

			-- return is_modifiable and is_savable_ft and not exclude_name and not exclude_ft
			if is_modifiable and is_writable and is_normal_buffer and is_savable_ft then
				vim.cmd("update")
			end
		end,
		group = group,
	})
end

local function hiddenFugitive()
	local group = api.nvim_create_augroup("HiddenFugitive", {
		clear = true,
	})

	api.nvim_create_autocmd({ "BufReadPost" }, {
		pattern = "fugitive://*",
		command = "set bufhidden=delete",
		group = group,
	})
end

local function wipeRegisters()
	api.nvim_create_user_command(
		"WipeReg",
		"for i in range(34,122) | silent! call setreg(nr2char(i), []) | endfor",
		{ bang = true }
	)
	local group = api.nvim_create_augroup("VimStartup", {
		clear = true,
	})

	api.nvim_create_autocmd({ "VimEnter" }, {
		pattern = "*",
		command = "WipeReg",
		group = group,
	})
end

local function highlightedYank()
	local group = api.nvim_create_augroup("HighlightedYank", {
		clear = true,
	})

	api.nvim_create_autocmd({ "TextYankPost" }, {
		pattern = "*",
		callback = function()
			vim.highlight.on_yank({ higroup = "Visual", timeout = 250, on_visual = false })
		end,
		group = group,
	})
end

local function disableGoFmtForSpecialBuffers()
	local group = api.nvim_create_augroup("DisableGoFmtSpecialBuffers", {
		clear = true,
	})

	-- Disable vim-go formatting for DAP REPL and other special buffers
	api.nvim_create_autocmd({ "FileType" }, {
		pattern = "dap-repl,dapui_console",
		callback = function()
			vim.b.go_fmt_autosave = 0
		end,
		group = group,
		desc = "Disable vim-go auto-formatting for DAP REPL buffers",
	})

	-- Also disable for any buffer with prompt or terminal buftype
	api.nvim_create_autocmd({ "BufEnter", "BufNew", "BufWinEnter" }, {
		pattern = "*",
		callback = function()
			if vim.bo.buftype == "prompt" or vim.bo.buftype == "terminal" or vim.bo.buftype == "nofile" then
				vim.b.go_fmt_autosave = 0
			end
		end,
		group = group,
		desc = "Disable vim-go auto-formatting for special buffer types",
	})
end

function M.setup()
	autosave()
	hiddenFugitive()
	wipeRegisters()
	highlightedYank()
	disableGoFmtForSpecialBuffers()
end

return M
