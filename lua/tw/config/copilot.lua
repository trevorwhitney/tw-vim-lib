local M = {}

local function configure()
  vim.g.copilot_no_tab_map = true
  vim.api.nvim_set_var("copilot_filetypes", {
    ["dap-repl"] = false,
  })
end

local function configureKeymap()
  local keymap = {
    name = "Copilot",
    ["<C-n>"] = { "<Plug>(copilot-next)", "Next" },
    ["<C-p>"] = { "<Plug>(copilot-previous)", "Previous" },
  }

  local whichkey = require("which-key")

  whichkey.register(keymap, {
    mode = "i",
    prefix = nil,
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  vim.keymap.set(
    "i",
    "<Plug>(vimrc:copilot-dummy-map)",
    'copilot#Accept("")',
    { silent = true, expr = true, desc = "Copilot dummy accept, needed for nvim-cmp" }
  )
end

function M.setup()
  configure()
  configureKeymap()
end

return M
