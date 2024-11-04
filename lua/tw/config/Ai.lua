local M = {}
local lspkind = require("lspkind")
local supermaven = require("supermaven-nvim")

local function configureCopilot()
  local copilot = require("copilot")
  copilot.setup({
    suggestion = {
      auto_trigger = true,
    },
    filetypes = {
      ["dap-repl"] = false,
    },
  })
end

local function configureSupermaven()
  supermaven.setup({
    -- disable_keymaps = true,
    keymaps = {
      accept_suggestion = "<C-f>",
      clear_suggestion = "<C-]>",
      accept_word = "<C-j>",
    }
  })

  lspkind.init({
    symbol_map = {
      Supermaven = "",
    },
  })

  vim.api.nvim_set_hl(0, "CmpItemKindSupermaven", { fg = "#6CC644" })
end

local function configureCopilotKeymap()
  local suggestion = require("copilot.suggestion")
  local keymap = {
    { "<C-j>", function() suggestion.next() end,     desc = "Copilot Next",     mode = "i", nowait = false, remap = false },
    { "<C-k>", function() suggestion.previous() end, desc = "Copliot Previous", mode = "i", nowait = false, remap = false },
    { "<C-f>", function() suggestion.accept() end,   desc = "Copliot Accept",   mode = "i", nowait = false, remap = false },
    { "<C-g>", function() suggestion.dismiss() end,  desc = "Copliot Dismiss",  mode = "i", nowait = false, remap = false },
  }

  local wk = require("which-key")
  wk.add(keymap)
end

function M.setup()
  -- configureCopilot()
  -- configureCopilotKeymap()

  configureSupermaven()
end

return M
