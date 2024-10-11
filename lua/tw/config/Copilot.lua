local M = {}

local function configure()
  vim.g.copilot_no_tab_map = true
  vim.api.nvim_set_var("copilot_filetypes", {
    ["dap-repl"] = false,
  })

  -- require("CopilotChat").setup({
  --   debug = false, -- Enable debugging
  --   -- See Configuration section for rest
  --   -- https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/canary/lua/CopilotChat/config.lua
  -- })
end

local function configureKeymap()
  local keymap = {
    { "<C-j>", "<Plug>(copilot-next)",     desc = "Copilot Next",     mode = "i", nowait = false, remap = false },
    { "<C-k>", "<Plug>(copilot-previous)", desc = "Copliot Previous", mode = "i", nowait = false, remap = false },
  }

  local wk = require("which-key")
  wk.add(keymap)

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
