local M = {}

local fn = vim.fn

local function escapeNewlinesAndForwardSlashes(text)
	local escape_newlines = fn.substitute(text, "\n", "", "g")
	return fn.substitute(escape_newlines, "/", "\\/", "g")
end

function M.currentSelectionForLiveGrep(text)
	local escape_slashes = fn.substitute(text, "\\", "\\\\\\\\", "g")
	return escapeNewlinesAndForwardSlashes(escape_slashes)
end

function M.currentSelectionForLiveGrepRaw(text)
	local escape_slashes = fn.substitute(text, "\\", "\\\\\\", "g")
	return escapeNewlinesAndForwardSlashes(escape_slashes)
end

return M
