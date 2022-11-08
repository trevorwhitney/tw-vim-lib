local M = {}

function M.diffSplit(commit)
  vim.cmd("Gdiffsplit " .. commit)
end

return M
