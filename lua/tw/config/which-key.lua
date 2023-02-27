local M = {}

local function mapKeys(which_key)
  local leaderKeymap = {
    -- Buffers
    b = {
      name = "Buffers",
      f = { "<cmd>Telescope buffers<cr>", "Find" },
      n = { "<cmd>bnext<cr>", "Next" },
      p = { "<cmd>bprevious<cr>", "Next" },
    },
    B = { "<cmd>Telescope buffers<cr>", "Find Buffer" },

    -- Find
    f = { "<cmd>Telescope git_files<cr>", "Find File (Git)" },
    F = { "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>", "Find Grep" },
    R = { "<cmd>Telescope resume<cr>", "Resume Find" },
    ["*"] = {
      "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>",
      "Find Grep (Current Word)",
    },

    s = {
      name = "Search",
      f = { "<cmd>Telescope find_files<cr>", "File (All)" },
      h = { "<cmd>Telescope help_tags<cr>", "Help Tags" },
      k = { "<cmd>Telescope keymaps<cr>", "Keymaps" },
      o = { "<cmd>Telescope oldfiles<cr>", "Recent (Old) Files" },
      p = { "<cmd>Telescope projects<cr>", "Projects" },
      r = { "<cmd>Telescope resume<cr>", "Resume" },
      s = { "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", "LSP Symbols" },
      t = { "<cmd>Telescope treesitter<cr>", "Treesitter Symbol" },
    },
    ["\\"] = { "<cmd>NvimTreeToggle<cr>", "NvimTree" },
    ["|"] = { "<cmd>NvimTreeFindFile<cr>", "NvimTree (Current File)" },
    m = {
      name = "Easy Motion",
      w = { "<Plug>(easymotion-overwin-w)", "Word" },
    },
  }

  which_key.register(leaderKeymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  which_key.register({
    r = {
      name = "Refactor",
      p = { ":%s/<C-r><C-w>/", "Replace (Word)" },
    },
  }, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = false,
    noremap = true,
    nowait = false,
  })

  vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
  local leaderVisualKeymap = {
    ["*"] = {
      "\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
      "Search Current Selection",
    },
    r = {
      name = "Refactor",
      r = { "<Esc><cmd>lua require('telescope').extensions.refactoring.refactors()<CR>", "Refactor Selection" },
    },
    z = { ":'<,'>sort<cr>", "sort" },
  }

  which_key.register(leaderVisualKeymap, {
    mode = "v",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local noLeaderKeymap = {
    ["\\"] = {
      name = "Windows",
      o = { "<cmd>Telescope lsp_document_symbols<cr>", "Outline" },
      s = { "<cmd>Git<cr>", "Git Status" },
      S = { "<cmd>Telescope git_status<cr>", "Git Status (Telescope)" },
      p = { "<cmd>pclose<cr>", "Close Preview" },
      b = { "<cmd>Branches<cr>", "Branches" },
      t = { "<cmd>Telescope tagstack<cr>", "Tag Stack" },
      l = { "<cmd>call ToggleLocationList()<cr>", "Location List" },
      q = { "<cmd>call ToggleQuickfixList()<cr>", "Quickfix" },
    },
  }

  which_key.register(noLeaderKeymap, {
    mode = "n",
    prefix = nil,
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = true,
  })

  for _, mode in ipairs({ "x", "s", "o" }) do
    which_key.register({
      m = {
        name = "Easy Motion",
        w = { "<Plug>(easymotion-bd-w)", "Word" },
      },
    }, {
      mode = mode,
      prefix = "<leader>",
      buffer = nil,
      silent = true,
      noremap = true,
      nowait = true,
    })
  end
end

function M.setup()
  local which_key = require("which-key")
  which_key.setup({
    window = {
      border = "single",
    },
  })

  mapKeys(which_key)
end

return M
