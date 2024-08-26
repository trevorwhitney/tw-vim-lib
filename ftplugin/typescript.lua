local M = {}

local function options()
  vim.cmd("setlocal tabstop=2")
  vim.cmd("setlocal shiftwidth=2")
  vim.cmd("setlocal expandtab")
end

local function keybindings()
  local whichkey = require("which-key")
  local keymap =
  {
    { "<leader>d",  group = "Debug",                                                  nowait = false, remap = false },
    { "<leader>dd", ":w<cr> <cmd>lua require('tw.languages.typescript').debug()<cr>", desc = "Debug", nowait = false, remap = false },
  }

  whichkey.add(keymap)
end

function M.ftplugin()
  options()
  keybindings()
end

M.ftplugin()
