local M = {}

function M.setup()
  -- light background
  vim.opt.background = "light"
  vim.opt.termguicolors = true

  -- solarized
  vim.g.solarized_italic_comments = true
  vim.g.solarized_italic_keywords = true
  vim.g.solarized_italic_functions = true
  vim.g.solarized_italic_variables = false
  vim.g.solarized_contrast = true
  vim.g.solarized_borders = true
  vim.g.solarized_disable_background = true

  -- Load dawnfox colorscheme
  vim.cmd("colorscheme dayfox")

  -- Load solarized colorscheme
  -- require("solarized").set()
end

return M
