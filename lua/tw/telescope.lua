local M = {}

local fn = vim.fn

local function escapeNewlinesAndForwardSlashes(text)
	local escape_newlines = fn.substitute(text, "\n", "", "g")
	return fn.substitute(escape_newlines, "/", "\\/", "g")
end

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

return M
