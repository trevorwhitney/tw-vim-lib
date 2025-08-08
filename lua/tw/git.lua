local M = {}

local function configureGitsigns()
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
        { "<leader>g",  group = "Git",                                                                  nowait = false,                        remap = false },
        { "<leader>gS", "<cmd>lua require('gitsigns').stage_buffer()<cr>",                              desc = "Stage Buffer",                 nowait = false, remap = false },
        { "<leader>gU", "<cmd>lua require('gitsigns').reset_buffer_index()<cr>",                        desc = "Reset Buffer Index",           nowait = false, remap = false },
        { "<leader>gW", "<cmd>Gwrite!<cr>",                                                             desc = "Git write",                    nowait = false, remap = false },
        { "<leader>gX", "<cmd>lua require('gitsigns').reset_buffer()<cr>",                              desc = "Reset Buffer",                 nowait = false, remap = false },
        { "<leader>gb", "<cmd>lua require('gitsigns').blame_line({ full = true })<cr>",                 desc = "Blame",                        nowait = false, remap = false },
        { "<leader>gc", "<cmd>lua require('gitsigns').toggle_current_line_blame()<cr>",                 desc = "Toggle Current Line Blame",    nowait = false, remap = false },
        { "<leader>gd", "<cmd>lua require('tw.git').diffSplit(vim.fn.input('[Commit] > '))<cr>", desc = "Diff Split (Against Commit)",  nowait = false, remap = false },
        { "<leader>gh", ":0Gclog!<cr>",                                                                 desc = "History",                      nowait = false, remap = false },
        { "<leader>gk", "Git commit<cr>",                                                               desc = "Commit",                       nowait = false, remap = false },
        { "<leader>gl", ":<C-u>Git log -n 50 --graph --decorate --oneline<cr>",                         desc = "Log",                          nowait = false, remap = false },
        { "<leader>go", "<cmd>lua require('tw.git').browseCurrentLine()<cr>",                    desc = "Open Current Line in Browser", nowait = false, remap = false },
        { "<leader>gp", "<cmd>lua require('gitsigns').preview_hunk()<cr>",                              desc = "Preview Hunk",                 nowait = false, remap = false },
        { "<leader>gs", "<cmd>lua require('gitsigns').stage_hunk()<cr>",                                desc = "Stage Hunk",                   nowait = false, remap = false },
        { "<leader>gu", "<cmd>lua require('gitsigns').undo_stage_hunk()<cr>",                           desc = "Undo Stage Hunk",              nowait = false, remap = false },
        { "<leader>gw", "<cmd>Gwrite<cr>",                                                              desc = "Git write",                    nowait = false, remap = false },
        { "<leader>gx", "<cmd>lua require('gitsigns').reset_hunk()<cr>",                                desc = "Reset Hunk",                   nowait = false, remap = false },

        { "ih",         "<cmd>lua require('gitsigns').select_hunk()<cr>",                               desc = "Select In Hunk",               mode = "o",     nowait = false, remap = false },

        { "go",         ":'<,'>GBrowse<cr>",                                                            desc = "Open in Browser",              mode = "x",     nowait = false, remap = false },
        { "ih",         "<cmd>lua require('gitsigns').select_hunk()<cr>",                               desc = "Select In Hunk",               mode = "x",     nowait = false, remap = false },
      }

      local whichkey = require("which-key")
      whichkey.add(keymap)
    end,
  })
end

local function configureDiffview()
  local actions = require("diffview.actions")
  require("diffview").setup({
    keymaps = {
      disable_defaults = true,
      view = {
        { "n", "[x", actions.prev_conflict, { desc = "In the merge-tool: jump to the previous conflict" } },
        { "n", "]x", actions.next_conflict, { desc = "In the merge-tool: jump to the next conflict" } },
        { "n", "<leader>b", actions.toggle_files,  { desc = "Toggle the file panel." } },
      },
      file_panel = {
        { "n", "-",  actions.toggle_stage_entry, { desc = "Stage / unstage the selected entry" } },
        { "n", "s",  actions.toggle_stage_entry, { desc = "Stage / unstage the selected entry" } },
        { "n", "[x", actions.prev_conflict,      { desc = "Go to the previous conflict" } },
        { "n", "]x", actions.next_conflict,      { desc = "Go to the next conflict" } },
        { "n", "g?", actions.help("file_panel"), { desc = "Open the help panel" } },
        { "n", "<leader>b", actions.toggle_files,       { desc = "Toggle the file panel" } },
      }
    },
  })
end

function M.setup()
  configureGitsigns()
  configureDiffview()
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
