local M = {}

local function setup()
  require("gitsigns").setup({
    current_line_blame = true,
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      local navigationKeymap = {
        name = "Gitsigns Navigation",
        ["]"] = {
          c = {
            function()
              if vim.wo.diff then
                return "]c"
              end
              vim.schedule(function()
                gs.next_hunk({ preview = true })
              end)
              return "<Ignore>"
            end,
            "Next Git Hunk",
          },
        },
        ["["] = {
          c = {
            function()
              if vim.wo.diff then
                return "[c"
              end
              vim.schedule(function()
                gs.prev_hunk({ preview = true })
              end)
              return "<Ignore>"
            end,
            "Previous Git Hunk",
          },
        },
      }

      local whichkey = require("which-key")
      whichkey.register(navigationKeymap, {
        mode = "n",
        prefix = nil,
        buffer = bufnr,
        silent = true,
        noremap = true,
        nowait = false,
      })

      local gitKeymap = {
        g = {
          name = "Git",
          b = { "<cmd>lua require('gitsigns').blame_line({ full = true })<cr>", "Blame" },
          c = {
            "<cmd>lua require('gitsigns').toggle_current_line_blame()<cr>",
            "Toggle Current Line Blame",
          },

          d = { ":Gdiffsplit<cr>", "Diff Split" },
          D = { "<cmd>lua require('tw.git').diffSplit(vim.fn.input('[Commit] > '))<cr>", "Diff Split (Against Commit)" },

          p = { "<cmd>lua require('gitsigns').preview_hunk()<cr>", "Preview Hunk" },

          r = { "<cmd>lua require('gitsigns').reset_hunk()<cr>", "Reset Hunk" },
          R = { "<cmd>lua require('gitsigns').reset_buffer()<cr>", "Reset Buffer" },

          s = { "<cmd>lua require('gitsigns').stage_hunk()<cr>", "Stage Hunk" },
          S = { "<cmd>lua require('gitsigns').stage_buffer()<cr>", "Stage Buffer" },

          u = { "<cmd>lua require('gitsigns').undo_stage_hunk()<cr>", "Undo Stage Hunk" },
          U = { "<cmd>lua require('gitsigns').reset_buffer_index()<cr>", "Reset Buffer Index" },

          o = { ":GitBrowse<cr>", "Open in Browser" },

          k = { "Git commit<cr>", "Commit" },

          h = { ":0Gclog!<cr>", "History" },
          l = { ":<C-u>Git log -n 50 --graph --decorate --oneline<cr>", "Log" },
        },
      }

      whichkey.register(gitKeymap, {
        mode = "n",
        prefix = "<leader>",
        buffer = bufnr,
        silent = true,
        noremap = true,
        nowait = false,
      })

      local operatorPendingKeymap = {
        i = {
          h = { "<cmd>lua require('gitsigns').select_hunk()<cr>", "Select In Hunk" },
        },
      }

      whichkey.register(operatorPendingKeymap, {
        mode = "o",
        prefix = nil,
        buffer = bufnr,
        silent = true,
        noremap = true,
        nowait = false,
      })

      local visualKeymap = {
        i = {
          h = { "<cmd>lua require('gitsigns').select_hunk()<cr>", "Select In Hunk" },
        },
        g = {
          o = { ":'<,'>GBrowse<cr>", "Open in Browser" },
        },
      }

      whichkey.register(visualKeymap, {
        mode = "x",
        prefix = nil,
        buffer = bufnr,
        silent = true,
        noremap = true,
        nowait = false,
      })
    end,
  })
end

function M.setup()
  setup()
end

return M
