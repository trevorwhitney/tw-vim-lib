local trouble = require("trouble")
local telescope = require("telescope")
local actions = require("telescope.actions")
local fn = vim.fn
local function openTroubleQF(prompt_bufnr)
	actions.send_to_qflist(prompt_bufnr)
	trouble.open("quickfix")
end

local function configure()
	telescope.load_extension("fzf")
	telescope.load_extension("refactoring")
	telescope.load_extension("dap")
	telescope.load_extension("ui-select")
	telescope.load_extension("aerial")

	telescope.setup({
		pickers = {
			colorscheme = {
				enable_preview = true,
			},
		},
		defaults = {
			mappings = {
				i = { ["<C-q>"] = openTroubleQF },
				n = { ["<C-q>"] = openTroubleQF },
			},
		},
	})
end

local function escapeNewlinesAndForwardSlashes(text)
	local escape_newlines = fn.substitute(text, "\n", "", "g")
	return fn.substitute(escape_newlines, "/", "\\/", "g")
end

local M = {}

function M.current_selection(text)
	local escape_slashes = fn.substitute(text, "\\", "\\\\\\", "g")
	return escapeNewlinesAndForwardSlashes(escape_slashes)
end

function M.live_grep_args(text)
	require("telescope").extensions.live_grep_args.live_grep_args({ default_text = '"' .. text .. '"' })
end

function M.dynamic_workspace_symbols(text)
	require("telescope.builtin").lsp_dynamic_workspace_symbols({ default_text = text })
end

function M.setup()
	configure()
end

return M
