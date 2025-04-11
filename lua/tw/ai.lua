local M = {}
local lspkind = require("lspkind")
local supermaven = require("supermaven-nvim")

local function configureSupermaven()
  supermaven.setup({
    disable_keymaps = true,
  })

  lspkind.init({
    symbol_map = {
      Supermaven = "",
    },
  })

  vim.api.nvim_set_hl(0, "CmpItemKindSupermaven", { fg = "#6CC644" })
end

local function configureSupermavenKeymap()
  local completion_preview = require("supermaven-nvim.completion_preview")

  local keymap = {
    { "<C-f>", completion_preview.on_accept_suggestion,      desc = "Supermaven Accept",     mode = "i", nowait = false, remap = false },
    { "<C-]>", completion_preview.on_dispose_inlay,          desc = "Supermaven Dismiss",    mode = "i", nowait = false, remap = false },
  }

  -- remove default <C-f> mapping so I don't scroll down the page
  -- when the supermaven completions aren't ready yet
  vim.keymap.del("i", "<C-f>")
  local wk = require("which-key")
  wk.add(keymap)
end


function M.setup()
  configureSupermaven()
  configureSupermavenKeymap()
end
return M
