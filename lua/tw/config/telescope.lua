local M = {}

local function mapKeys()
  -- TODO: migrate to which-key
  vim.fn["tw#telescope#MapKeys"]()

  vim.api.nvim_set_keymap(
    "v",
    "<leader>rr",
    "<Esc><cmd>lua require('telescope').extensions.refactoring.refactors()<CR>",
    { noremap = true, silent = true }
  )
end

local function configure()
  local telescope = require("telescope")
  telescope.load_extension("fzf")
  telescope.load_extension("projects")
  telescope.load_extension("refactoring")
  telescope.load_extension("dap")

  telescope.setup({})
end

function M.setup()
  mapKeys()
  configure()
end

return M
