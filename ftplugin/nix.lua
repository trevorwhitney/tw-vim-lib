local M = {}

local function commentary()
	vim.cmd("setlocal commentstring=#\\ \\%s")
end

function M.setup()
	commentary()
end

M.setup()
