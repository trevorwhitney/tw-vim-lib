local M = {}

local function configure()
  local telescope = require("telescope")
  telescope.load_extension("fzf")
  telescope.load_extension("projects")
  telescope.load_extension("refactoring")
  telescope.load_extension("dap")

  telescope.setup({
    pickers = {
      colorscheme = {
        enable_preview = true,
      },
    },
  })
end

function M.setup()
  configure()
end

return M