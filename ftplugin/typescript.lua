local M = {}

local function options()
  vim.cmd("setlocal tabstop=2")
  vim.cmd("setlocal shiftwidth=2")
  vim.cmd("setlocal expandtab")
end

local function keybindings()
  local runKeymap = {
    d = {
      name = "Debug",
      d = { ":w<cr> <cmd>lua require('tw.languages.typescript').debug()<cr>", "Debug" },
    },
  }

  local whichkey = require("which-key")

  whichkey.register(runKeymap, {
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
