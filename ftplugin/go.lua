local M = {}

local function settings()
  local set = vim.opt
  set.tabstop = 2
  set.shiftwidth = 2
end

local function keybindings()
  local keymap = {
    { "<leader>d", group = "Debug", nowait = false, remap = false },
    {
      "<leader>dA",
      function()
        local args = vim.fn.input({ prompt = "Args: " })
        vim.cmd("write")
        require("tw.languages.go").debug_relative({ args })
      end,
      desc = "Debug Relative (Arguments)",
      nowait = false,
      remap = false,
    },
    {
      "<leader>dD",
      function()
        local go = require("tw.languages.go")
        local test_name = go.get_test_name(true)

        vim.cmd("update")
        go.debug(test_name)
      end,
      desc = "Debug (Prompt for Name)",
      nowait = false,
      remap = false,
    },
    {
      "<leader>da",
      function()
        vim.cmd("write")
        require("tw.languages.go").debug_relative()
      end,
      desc = "Debug Relative",
      nowait = false,
      remap = false,
    },
    {
      "<leader>dd",
      function()
        local go = require("tw.languages.go")

        vim.cmd("update")
        go.debug()
      end,
      desc = "Debug",
      nowait = false,
      remap = false,
    },
    {
      "<leader>dm",
      function()
        vim.cmd("update")
        require("tw.languages.go").remote_debug(
          vim.fn.input({ prompt = "Remote Path: " }),
          vim.fn.input({ prompt = "Port: " })
        )
      end,
      desc = "Remote Debug",
      nowait = false,
      remap = false,
    },

    { "<leader>t", group = "Test",  nowait = false, remap = false },
    {
      "<leader>tT",
      function()
        local go = require("tw.languages.go")
        local package_name = "./" .. vim.fn.expand("%:h")

        local test_name = go.get_test_name()

        vim.cmd("update")
        vim.fn.execute(string.format("Dispatch go test -v -run '%s' %s ", test_name, package_name))
      end,
      desc = "Test (Prompt for Name)",
      nowait = false,
      remap = false,
    },
    {
      "<leader>ta",
      ":w<cr> :GolangTestCurrentPackage<cr>",
      desc = "Package Tests",
      nowait = false,
      remap = false,
    },


    { "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
    {
      "<leader>ct",
      function()
        local go = require("tw.languages.go")
        local package_name = "./" .. vim.fn.expand("%:h")

        local test_name = go.get_test_name(false)

        vim.cmd("update")
        vim.fn["VimuxSendText"](string.format("/run go test -v -run \'%s\' %s", test_name, package_name))
        vim.fn["VimuxSendKeys"]("Enter")
      end,
      desc = "Aider Test",
      nowait = false,
      remap = false,
    },
    {
      "<leader>cT",
      function()
        local go = require("tw.languages.go")
        local package_name = "./" .. vim.fn.expand("%:h")

        local test_name = go.get_test_name(true)

        vim.cmd("update")
        vim.fn["VimuxSendText"](string.format("/run go test -v -run \'%s\' %s", test_name, package_name))
        vim.fn["VimuxSendKeys"]("Enter")
      end,
      desc = "Aider Test (Prompt for Name)",
      nowait = false,
      remap = false,
    },

    {
      "<leader>gT",
      ":<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>",
      desc = "Go to Alternate (In Vertical Split)",
      nowait = false,
      remap = false,
    },
    {
      "<leader>gi",
      ":<C-u>GoImpl<cr>",
      desc = "Go Implement Interface",
      nowait = false,
      remap = false,
    },
    {
      "<leader>gt",
      ":<C-u>GoAlternate<cr>",
      desc = "Go to Alternate",
      nowait = false,
      remap = false,
    },

    {
      "<leader>tj",
      ":GoAddTags json<cr>",
      desc = "Add JSON Tags",
      nowait = false,
      remap = false,
    },
    {
      "<leader>tx",
      ":GoRemoveTags<cr>",
      desc = "Remove Tags",
      nowait = false,
      remap = false,
    },
    {
      "<leader>ty",
      ":GoAddTags yaml<cr>",
      desc = "Add YAML Tags",
      nowait = false,
      remap = false,
    },
  }

  local whichkey = require("which-key")
  whichkey.add(keymap)
end

function M.setup()
  settings()
  keybindings()
end

M.setup()
