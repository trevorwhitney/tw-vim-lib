local M = {}

function M.open_in_select(filename)
  require('nvim-tree.lib').open_file("edit", filename)
end

return M
