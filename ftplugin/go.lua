local M = {}

local function settings()
  local set = vim.opt
  set.tabstop = 2
  set.shiftwidth = 2

  vim.g["go_code_completion_enabled"] = 0
  vim.g["go_def_mapping_enabled"] = 0
  vim.g["go_build_tags"] = "e2e_gem,requires_docker"
  vim.g["go_textobj_enabled"] = 0
  vim.g["go_gopls_enabled"] = 0
end

local function keybindings()
  local runKeymap = {
    r = {
      name = "Run",
      p = { ":w<cr> :GolangTestCurrentPackage<cr>", "Current Package Tests" },

      t = { ":w<cr> <cmd>lua require('tw.languages.go').runTest()<cr>", "Focused Test" },
      T = {
        ":w<cr> <cmd>lua require('tw.languages.go').runTest(vim.fn.input('[Tags] > '))<cr>",
        "Focused Test (With Tags)",
      },

      d = { ":w<cr> <cmd>lua require('tw.languages.go').debug_go_test()<cr>", "Debug Focused Test" },
      D = {
        ":w<cr> <cmd>lua require('tw.languages.go').debug_go_test(vim.fn.input('[Tags] > '))<cr>",
        "Debug Focused Test",
      },
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

  local goToKeymap = {
    name = "Go To",
    g = {
      t = { ":<C-u>GoAlternate<cr>", "Alternate" },
      T = { ":<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>", "Alternate (In Vertical Split)" },
      i = { ":<C-u>GoImpl<cr>", "Implementation" },
    },
  }

  whichkey.register(goToKeymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local tagsKeymap = {
    name = "Go Tags",
    t = {
      j = { ":GoAddTags json<cr>", "Add JSON Tags" },
      y = { ":GoAddTags yaml<cr>", "Add YAML Tags" },
      x = { ":GoRemoveTags<cr>", "Remove Tags" },
    },
  }

  whichkey.register(tagsKeymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })
end

function M.setup()
  settings()
  keybindings()
end

M.setup()
