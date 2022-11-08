local M = {}

function M.diffSplit(commit)
  vim.cmd("Gdiffsplit " .. commit)
end

function M.browseCurrentLine()
  local line = vim.fn.getline(".")
  vim.cmd(line .. "GBrowse")
end

return M
