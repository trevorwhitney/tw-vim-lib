local M = {}

function M.diffSplit(commit)
  vim.cmd("Gdiffsplit " .. commit)
end

function M.browseCurrentLine()
  local linenum = vim.api.nvim_win_get_cursor(0)
  vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
