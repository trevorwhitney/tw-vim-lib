local M = {}

local which_key = require("which-key")

local function mapKeys()
  local keymap = {
    f = {
      name = "Find",
      a = { "<cmd>Telescope find_files<cr>", "Files (All)" },
      b = { "<cmd>Telescope buffers<cr>", "Buffers" },
      f = { "<cmd>Telescope git_files<cr>", "Files (Git)" },
      g = { "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>", "Grep (Live)" },
      h = { "<cmd>Telescope help_tags<cr>", "Help Tags" },
      o = { "<cmd>Telescope oldfiles<cr>", "Recent (Old) Files" },
      p = { "<cmd>Telescope projects<cr>", "Projects" },
      r = { "<cmd>Telescope resume<cr>", "Resume" },
      s = { "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", "LSP Symbols" },
      t = { "<cmd>Telescope treesitter<cr>", "Treesitter Symbol" },
      ["*"] = {
        "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>",
        "Current Word",
      },
    },
  }

  which_key.register(keymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local keymapNoLeader = {
    ["\\o"] = { "<cmd>Telescope lsp_document_symbols<cr>", "Outline" },
  }

  which_key.register(keymapNoLeader, {
    mode = "n",
    prefix = nil,
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  -- vim.cmd("command! -nargs=* TelescopeDynamicSymbols call v:lua.require('tw.telescope').dynamic_workspace_symbols(<q-args>)")
  vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
  local visualKeymap = {
    f = {
      name = "Find",
      ["*"] = {
        "\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
        "Current Selection",
      },
    },
  }

  which_key.register(visualKeymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  vim.api.nvim_set_keymap(
    "v",
    "<leader>rr",
    "<Esc><cmd>lua require('telescope').extensions.refactoring.refactors()<CR>",
    { noremap = true, silent = true }
  )
end

local function configure()
  local telescope = require("telescope")
  telescope.load_extension("fzf")
  telescope.load_extension("projects")
  telescope.load_extension("refactoring")
  telescope.load_extension("dap")

  telescope.setup({})
end

function M.setup()
  mapKeys()
  configure()
end

return M
