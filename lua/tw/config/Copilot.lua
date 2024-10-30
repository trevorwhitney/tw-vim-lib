local M = {}
local copilot = require("copilot")
local function configure()
  copilot.setup({
    suggestion = {
      auto_trigger = true,
    },
    filetypes = {
      ["dap-repl"] = false,
    },
  })
end

local suggestion = require("copilot.suggestion")
local function configureKeymap()
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
  configure()
  configureKeymap()
end

return M
