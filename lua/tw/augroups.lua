local M = {}
local api = vim.api
local buffer_util = require("tw.buffer-util")

local function autosave()
	local group = api.nvim_create_augroup("Autosave", {
		clear = true,
	})

	api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
		pattern = "*",
		callback = function(event)
			if buffer_util.should_autosave(event.buf) then
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
