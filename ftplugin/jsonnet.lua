local M = {}

local function options()
  vim.cmd("setlocal indentexpr=")
end

local function keybindings()
  local whichkey = require("which-key")
  local keymap = {
    e = {
      name = "Execute",
      b = { ":call tw#jsonnet#eval()<cr>", "Evaluate Jsonnet" },
    },
  }

  whichkey.register(keymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })
end

function M.ftplugin()
  options()
  keybindings()
end

M.ftplugin()
