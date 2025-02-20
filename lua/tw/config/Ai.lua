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

  local wk = require("which-key")
  wk.add(keymap)
end

local function configureAiderKeymap()
  local keymap = {
    { "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>ca", function() vim.fn.execute("VimuxRunCommand(\"aider --architect\")") end , desc = "Open Aider" },
      --TODO: add a keymap `<leader>cq` that will add all the files from the quickfix list to aider
    },
  }

  local wk = require("which-key")
  wk.add(keymap)
end

function M.setup()
  configureSupermaven()
  configureSupermavenKeymap()

  configureAiderKeymap()
end
return M
