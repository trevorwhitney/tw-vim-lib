local M = {}

local function mapKeys(which_key)
  local leaderKeymap = {
    b = { "<cmd>Telescope buffers<cr>", "Find Buffer" },
    --TODO: remove when transitioned to lower case b
    B = { "<cmd>Telescope buffers<cr>", "Find Buffer" },

    -- Test
    t = {
      name = "Test",
      t = { ":w<cr> :TestNearest<cr>", "Test Nearest" },
      l = { ":w<cr> :TestLast<cr>", "Test Last" },
      f = { ":w<cr> :TestFile<cr>", "Test File" },
    },

    -- Find
    f = { "<cmd>Telescope git_files<cr>", "Find File (Git)" },
    F = { "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>", "Find Grep" },

    m = {
      name = "Easy Motion",
      w = { "<Plug>(easymotion-overwin-w)", "Word" },
    },

    p = {
      name = "Print",
      d = { "<cmd>lua require('refactoring').debug.printf({below = false})<CR>", "Print Debug Line" },
      v = { "<cmd>lua require('refactoring').debug.print_var()<CR>", "Print Var" },
      c = { "<cmd>lua require('refactoring').debug.cleanup()<CR>", "Cleanup Print Statements" },
    },

    -- Refactor
    r = {
      name = "Refactor",
      r = { "<cmd>lua require('telescope').extensions.refactoring.refactors()<CR>", "Refactor Menu" },
      p = { "<cmd>lua require('replacer').run()<cr>", "Replacer" },
      -- Inline variable works in both visual and normal mode
      i = { "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>", "Inline Variable" },
      -- Extract block only works in normal mode
      bl = { "<cmd>lua require('refactoring').refactor('Extract Block')<CR>", "Extract Block" },
      bf = { "<cmd>lua require('refactoring').refactor('Extract Block To File')<CR>", "Extract Block to File" },
    },

    R = { "<cmd>Telescope resume<cr>", "Resume Find" },
    ["*"] = {
      "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>",
      "Find Grep (Current Word)",
    },

    ["\\"] = { "<cmd>NvimTreeToggle<cr>", "NvimTree" },
    ["|"] = { "<cmd>NvimTreeFindFile<cr>", "NvimTree (Current File)" },
  }

  which_key.register(leaderKeymap, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
  local leaderVisualKeymap = {
    ["*"] = {
      "\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
      "Search Current Selection",
    },
    p = {
      name = "Print",
      v = { "<cmd>lua require('refactoring').debug.print_var()<CR>", "Print Var" },
    },

    r = {
      name = "Refactor",
      -- Extract function supports only visual mode
      e = { "<cmd>lua require('refactoring').refactor('Extract Function')<CR>", "Extract Function" },
      f = {
        "<cmd>lua require('refactoring').refactor('Extract Function To File')<CR>",
        "Extract Function To File",
      },
      -- Inline variable works in both visual and normal mode
      i = { "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>", "Inline Variable" },
      -- Extract variable supports only visual mode
      v = { "<cmd>lua require('refactoring').refactor('Extract Variable')<CR>", "Extract Variable" },
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
      S = { "<cmd>Telescope git_status<cr>", "Git Status (Telescope)" },

      b = { "<cmd>Branches<cr>", "Branches" },
      d = { "<cmd>Telescope diagnostics<CR>", "Diagnostic List" },
      l = { "<cmd>call ToggleLocationList()<cr>", "Location List" },
      m = { "<cmd>Telescope marks<cr>", "Marks" },
      o = { "<cmd>Telescope lsp_document_symbols<cr>", "Outline" },
      p = { "<cmd>pclose<cr>", "Close Preview" },
      q = { "<cmd>call ToggleQuickfixList()<cr>", "Quickfix" },
      s = { "<cmd>Git<cr>", "Git Status" },
      t = { "<cmd>Telescope tagstack<cr>", "Tag Stack" },
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
