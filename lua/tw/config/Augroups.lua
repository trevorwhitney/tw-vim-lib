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
			local is_writable = fn.filewritable(fn.expand(fn.bufname(buf))) == 1
			local is_normal_buffer = fn.getbufvar(buf, "&buftype") == ""

			local name = fn.bufname(buf)
			local name_re = vim.regex("^(fugitive|octo|\\[dap.*):?")
			local exclude_name = name_re:match_str(name)

			local ft = fn.getbufvar(buf, "&filetype")
			local is_savable_ft = not_in(ft, skip_fts)

			-- return is_modifiable and is_savable_ft and not exclude_name and not exclude_ft
			if is_modifiable and is_writable and is_normal_buffer and is_savable_ft and not exclude_name then
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

function M.setup()
	autosave()
	hiddenFugitive()
	wipeRegisters()
	highlightedYank()
end

return M
