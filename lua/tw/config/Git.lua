local M = {}

local function setup()
  require("gitsigns").setup({
    current_line_blame = true,
    -- highlight numbers instead of using the sign column
    signcolumn = false,
    numhl = true,
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      local function map(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end

      map("n", "]c", function()
        if vim.wo.diff then
          return "]c"
        end
        vim.schedule(function()
          gs.next_hunk()
        end)
        return "<Ignore>"
      end, { expr = true })

      map("n", "[c", function()
        if vim.wo.diff then
          return "[c"
        end
        vim.schedule(function()
          gs.prev_hunk()
        end)
        return "<Ignore>"
      end, { expr = true })

      local keymap = {
        { "<leader>g",  buffer = 1,                                                                     group = "Git", nowait = false,                        remap = false },
        { "<leader>gS", "<cmd>lua require('gitsigns').stage_buffer()<cr>",                              buffer = 1,    desc = "Stage Buffer",                 nowait = false, remap = false },
        { "<leader>gU", "<cmd>lua require('gitsigns').reset_buffer_index()<cr>",                        buffer = 1,    desc = "Reset Buffer Index",           nowait = false, remap = false },
        { "<leader>gW", "<cmd>Gwrite!<cr>",                                                             buffer = 1,    desc = "Git write",                    nowait = false, remap = false },
        { "<leader>gX", "<cmd>lua require('gitsigns').reset_buffer()<cr>",                              buffer = 1,    desc = "Reset Buffer",                 nowait = false, remap = false },
        { "<leader>gb", "<cmd>lua require('gitsigns').blame_line({ full = true })<cr>",                 buffer = 1,    desc = "Blame",                        nowait = false, remap = false },
        { "<leader>gc", "<cmd>lua require('gitsigns').toggle_current_line_blame()<cr>",                 buffer = 1,    desc = "Toggle Current Line Blame",    nowait = false, remap = false },
        { "<leader>gd", "<cmd>lua require('tw.config.Git').diffSplit(vim.fn.input('[Commit] > '))<cr>", buffer = 1,    desc = "Diff Split (Against Commit)",  nowait = false, remap = false },
        { "<leader>gh", ":0Gclog!<cr>",                                                                 buffer = 1,    desc = "History",                      nowait = false, remap = false },
        { "<leader>gk", "Git commit<cr>",                                                               buffer = 1,    desc = "Commit",                       nowait = false, remap = false },
        { "<leader>gl", ":<C-u>Git log -n 50 --graph --decorate --oneline<cr>",                         buffer = 1,    desc = "Log",                          nowait = false, remap = false },
        { "<leader>go", "<cmd>lua require('tw.config.Git').browseCurrentLine()<cr>",                    buffer = 1,    desc = "Open Current Line in Browser", nowait = false, remap = false },
        { "<leader>gp", "<cmd>lua require('gitsigns').preview_hunk()<cr>",                              buffer = 1,    desc = "Preview Hunk",                 nowait = false, remap = false },
        { "<leader>gs", "<cmd>lua require('gitsigns').stage_hunk()<cr>",                                buffer = 1,    desc = "Stage Hunk",                   nowait = false, remap = false },
        { "<leader>gu", "<cmd>lua require('gitsigns').undo_stage_hunk()<cr>",                           buffer = 1,    desc = "Undo Stage Hunk",              nowait = false, remap = false },
        { "<leader>gw", "<cmd>Gwrite<cr>",                                                              buffer = 1,    desc = "Git write",                    nowait = false, remap = false },
        { "<leader>gx", "<cmd>lua require('gitsigns').reset_hunk()<cr>",                                buffer = 1,    desc = "Reset Hunk",                   nowait = false, remap = false },

        { "ih",         "<cmd>lua require('gitsigns').select_hunk()<cr>",                               buffer = 1,    desc = "Select In Hunk",               mode = "o",     nowait = false, remap = false },

        { "go",         ":'<,'>GBrowse<cr>",                                                            buffer = 1,    desc = "Open in Browser",              mode = "x",     nowait = false, remap = false },
        { "ih",         "<cmd>lua require('gitsigns').select_hunk()<cr>",                               buffer = 1,    desc = "Select In Hunk",               mode = "x",     nowait = false, remap = false },
      }

      local whichkey = require("which-key")
      whichkey.add(keymap)
    end,
  })
end

function M.setup()
  setup()
end

function M.gpp()
  vim.cmd("Git pull --rebase")
  vim.cmd("Git push")
end

function M.diffSplit(commit)
  vim.cmd("Gdiffsplit " .. commit)
end

function M.toggleGitStatus()
  local fugitiveBuf = vim.fn.bufnr("fugitive://")
  if fugitiveBuf >= 0 and vim.fn.bufwinnr(fugitiveBuf) >= 0 then
    vim.cmd("bunload " .. fugitiveBuf)
  else
    vim.cmd("Git")
  end
end

function M.browseCurrentLine()
  local linenum = vim.api.nvim_win_get_cursor(0)
  vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
