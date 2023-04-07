local M = {}

local function options()
  vim.cmd("setlocal tabstop=4")
  vim.cmd("setlocal shiftwidth=4")
  vim.cmd("setlocal noexpandtab")
end

function M.ftplugin()
  options()
end

M.ftplugin()
