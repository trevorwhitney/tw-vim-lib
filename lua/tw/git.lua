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
    --   disable_defaults = false,
    --   view = {
    --     -- The `view` bindings are active in the diff buffers, only when the current
    --     -- tabpage is a Diffview.
    --     { "n", "<tab>",      actions.select_next_entry,             { desc = "Open the diff for the next file" } },
    --     { "n", "<s-tab>",    actions.select_prev_entry,             { desc = "Open the diff for the previous file" } },
    --     { "n", "[F",         actions.select_first_entry,            { desc = "Open the diff for the first file" } },
    --     { "n", "]F",         actions.select_last_entry,             { desc = "Open the diff for the last file" } },
    --     { "n", "gf",         actions.goto_file_edit,                { desc = "Open the file in the previous tabpage" } },
    --     { "n", "<C-w><C-f>", actions.goto_file_split,               { desc = "Open the file in a new split" } },
    --     { "n", "<C-w>gf",    actions.goto_file_tab,                 { desc = "Open the file in a new tabpage" } },
    --     { "n", "<leader>e",  actions.focus_files,                   { desc = "Bring focus to the file panel" } },
    --     { "n", "<leader>b",  actions.toggle_files,                  { desc = "Toggle the file panel." } },
    --     { "n", "g<C-x>",     actions.cycle_layout,                  { desc = "Cycle through available layouts." } },
    --     { "n", "[x",         actions.prev_conflict,                 { desc = "In the merge-tool: jump to the previous conflict" } },
    --     { "n", "]x",         actions.next_conflict,                 { desc = "In the merge-tool: jump to the next conflict" } },
    --     { "n", "<leader>co", actions.conflict_choose("ours"),       { desc = "Choose the OURS version of a conflict" } },
    --     { "n", "<leader>ct", actions.conflict_choose("theirs"),     { desc = "Choose the THEIRS version of a conflict" } },
    --     { "n", "<leader>cb", actions.conflict_choose("base"),       { desc = "Choose the BASE version of a conflict" } },
    --     { "n", "<leader>ca", actions.conflict_choose("all"),        { desc = "Choose all the versions of a conflict" } },
    --     { "n", "dx",         actions.conflict_choose("none"),       { desc = "Delete the conflict region" } },
    --     { "n", "<leader>cO", actions.conflict_choose_all("ours"),   { desc = "Choose the OURS version of a conflict for the whole file" } },
    --     { "n", "<leader>cT", actions.conflict_choose_all("theirs"), { desc = "Choose the THEIRS version of a conflict for the whole file" } },
    --     { "n", "<leader>cB", actions.conflict_choose_all("base"),   { desc = "Choose the BASE version of a conflict for the whole file" } },
    --     { "n", "<leader>cA", actions.conflict_choose_all("all"),    { desc = "Choose all the versions of a conflict for the whole file" } },
    --     { "n", "dX",         actions.conflict_choose_all("none"),   { desc = "Delete the conflict region for the whole file" } },
    --   },
    --   diff1 = {
    --     -- Mappings in single window diff layouts
    --     { "n", "g?", actions.help({ "view", "diff1" }), { desc = "Open the help panel" } },
    --   },
    --   diff2 = {
    --     -- Mappings in 2-way diff layouts
    --     { "n", "g?", actions.help({ "view", "diff2" }), { desc = "Open the help panel" } },
    --   },
    --   diff3 = {
    --     -- Mappings in 3-way diff layouts
    --     { { "n", "x" }, "2do", actions.diffget("ours"),           { desc = "Obtain the diff hunk from the OURS version of the file" } },
    --     { { "n", "x" }, "3do", actions.diffget("theirs"),         { desc = "Obtain the diff hunk from the THEIRS version of the file" } },
    --     { "n",          "g?",  actions.help({ "view", "diff3" }), { desc = "Open the help panel" } },
    --   },
    --   diff4 = {
    --     -- Mappings in 4-way diff layouts
    --     { { "n", "x" }, "1do", actions.diffget("base"),           { desc = "Obtain the diff hunk from the BASE version of the file" } },
    --     { { "n", "x" }, "2do", actions.diffget("ours"),           { desc = "Obtain the diff hunk from the OURS version of the file" } },
    --     { { "n", "x" }, "3do", actions.diffget("theirs"),         { desc = "Obtain the diff hunk from the THEIRS version of the file" } },
    --     { "n",          "g?",  actions.help({ "view", "diff4" }), { desc = "Open the help panel" } },
    --   },
    --   file_panel = {
    --     { "n", "j",             actions.next_entry,                    { desc = "Bring the cursor to the next file entry" } },
    --     { "n", "<down>",        actions.next_entry,                    { desc = "Bring the cursor to the next file entry" } },
    --     { "n", "k",             actions.prev_entry,                    { desc = "Bring the cursor to the previous file entry" } },
    --     { "n", "<up>",          actions.prev_entry,                    { desc = "Bring the cursor to the previous file entry" } },
    --     { "n", "<cr>",          actions.select_entry,                  { desc = "Open the diff for the selected entry" } },
    --     { "n", "o",             actions.select_entry,                  { desc = "Open the diff for the selected entry" } },
    --     { "n", "l",             actions.select_entry,                  { desc = "Open the diff for the selected entry" } },
    --     { "n", "<2-LeftMouse>", actions.select_entry,                  { desc = "Open the diff for the selected entry" } },
    --     { "n", "-",             actions.toggle_stage_entry,            { desc = "Stage / unstage the selected entry" } },
    --     { "n", "s",             actions.toggle_stage_entry,            { desc = "Stage / unstage the selected entry" } },
    --     { "n", "S",             actions.stage_all,                     { desc = "Stage all entries" } },
    --     { "n", "U",             actions.unstage_all,                   { desc = "Unstage all entries" } },
    --     { "n", "X",             actions.restore_entry,                 { desc = "Restore entry to the state on the left side" } },
    --     { "n", "L",             actions.open_commit_log,               { desc = "Open the commit log panel" } },
    --     { "n", "zo",            actions.open_fold,                     { desc = "Expand fold" } },
    --     { "n", "h",             actions.close_fold,                    { desc = "Collapse fold" } },
    --     { "n", "zc",            actions.close_fold,                    { desc = "Collapse fold" } },
    --     { "n", "za",            actions.toggle_fold,                   { desc = "Toggle fold" } },
    --     { "n", "zR",            actions.open_all_folds,                { desc = "Expand all folds" } },
    --     { "n", "zM",            actions.close_all_folds,               { desc = "Collapse all folds" } },
    --     { "n", "<c-b>",         actions.scroll_view(-0.25),            { desc = "Scroll the view up" } },
    --     { "n", "<c-f>",         actions.scroll_view(0.25),             { desc = "Scroll the view down" } },
    --     { "n", "<tab>",         actions.select_next_entry,             { desc = "Open the diff for the next file" } },
    --     { "n", "<s-tab>",       actions.select_prev_entry,             { desc = "Open the diff for the previous file" } },
    --     { "n", "[F",            actions.select_first_entry,            { desc = "Open the diff for the first file" } },
    --     { "n", "]F",            actions.select_last_entry,             { desc = "Open the diff for the last file" } },
    --     { "n", "gf",            actions.goto_file_edit,                { desc = "Open the file in the previous tabpage" } },
    --     { "n", "<C-w><C-f>",    actions.goto_file_split,               { desc = "Open the file in a new split" } },
    --     { "n", "<C-w>gf",       actions.goto_file_tab,                 { desc = "Open the file in a new tabpage" } },
    --     { "n", "i",             actions.listing_style,                 { desc = "Toggle between 'list' and 'tree' views" } },
    --     { "n", "f",             actions.toggle_flatten_dirs,           { desc = "Flatten empty subdirectories in tree listing style" } },
    --     { "n", "R",             actions.refresh_files,                 { desc = "Update stats and entries in the file list" } },
    --     { "n", "<leader>e",     actions.focus_files,                   { desc = "Bring focus to the file panel" } },
    --     { "n", "<leader>b",     actions.toggle_files,                  { desc = "Toggle the file panel" } },
    --     { "n", "g<C-x>",        actions.cycle_layout,                  { desc = "Cycle available layouts" } },
    --     { "n", "[x",            actions.prev_conflict,                 { desc = "Go to the previous conflict" } },
    --     { "n", "]x",            actions.next_conflict,                 { desc = "Go to the next conflict" } },
    --     { "n", "g?",            actions.help("file_panel"),            { desc = "Open the help panel" } },
    --     { "n", "<leader>cO",    actions.conflict_choose_all("ours"),   { desc = "Choose the OURS version of a conflict for the whole file" } },
    --     { "n", "<leader>cT",    actions.conflict_choose_all("theirs"), { desc = "Choose the THEIRS version of a conflict for the whole file" } },
    --     { "n", "<leader>cB",    actions.conflict_choose_all("base"),   { desc = "Choose the BASE version of a conflict for the whole file" } },
    --     { "n", "<leader>cA",    actions.conflict_choose_all("all"),    { desc = "Choose all the versions of a conflict for the whole file" } },
    --     { "n", "dX",            actions.conflict_choose_all("none"),   { desc = "Delete the conflict region for the whole file" } },
    --   },
    --   file_history_panel = {
    --     { "n", "g!",            actions.options,                    { desc = "Open the option panel" } },
    --     { "n", "<C-A-d>",       actions.open_in_diffview,           { desc = "Open the entry under the cursor in a diffview" } },
    --     { "n", "y",             actions.copy_hash,                  { desc = "Copy the commit hash of the entry under the cursor" } },
    --     { "n", "L",             actions.open_commit_log,            { desc = "Show commit details" } },
    --     { "n", "X",             actions.restore_entry,              { desc = "Restore file to the state from the selected entry" } },
    --     { "n", "zo",            actions.open_fold,                  { desc = "Expand fold" } },
    --     { "n", "zc",            actions.close_fold,                 { desc = "Collapse fold" } },
    --     { "n", "h",             actions.close_fold,                 { desc = "Collapse fold" } },
    --     { "n", "za",            actions.toggle_fold,                { desc = "Toggle fold" } },
    --     { "n", "zR",            actions.open_all_folds,             { desc = "Expand all folds" } },
    --     { "n", "zM",            actions.close_all_folds,            { desc = "Collapse all folds" } },
    --     { "n", "j",             actions.next_entry,                 { desc = "Bring the cursor to the next file entry" } },
    --     { "n", "<down>",        actions.next_entry,                 { desc = "Bring the cursor to the next file entry" } },
    --     { "n", "k",             actions.prev_entry,                 { desc = "Bring the cursor to the previous file entry" } },
    --     { "n", "<up>",          actions.prev_entry,                 { desc = "Bring the cursor to the previous file entry" } },
    --     { "n", "<cr>",          actions.select_entry,               { desc = "Open the diff for the selected entry" } },
    --     { "n", "o",             actions.select_entry,               { desc = "Open the diff for the selected entry" } },
    --     { "n", "l",             actions.select_entry,               { desc = "Open the diff for the selected entry" } },
    --     { "n", "<2-LeftMouse>", actions.select_entry,               { desc = "Open the diff for the selected entry" } },
    --     { "n", "<c-b>",         actions.scroll_view(-0.25),         { desc = "Scroll the view up" } },
    --     { "n", "<c-f>",         actions.scroll_view(0.25),          { desc = "Scroll the view down" } },
    --     { "n", "<tab>",         actions.select_next_entry,          { desc = "Open the diff for the next file" } },
    --     { "n", "<s-tab>",       actions.select_prev_entry,          { desc = "Open the diff for the previous file" } },
    --     { "n", "[F",            actions.select_first_entry,         { desc = "Open the diff for the first file" } },
    --     { "n", "]F",            actions.select_last_entry,          { desc = "Open the diff for the last file" } },
    --     { "n", "gf",            actions.goto_file_edit,             { desc = "Open the file in the previous tabpage" } },
    --     { "n", "<C-w><C-f>",    actions.goto_file_split,            { desc = "Open the file in a new split" } },
    --     { "n", "<C-w>gf",       actions.goto_file_tab,              { desc = "Open the file in a new tabpage" } },
    --     { "n", "<leader>e",     actions.focus_files,                { desc = "Bring focus to the file panel" } },
    --     { "n", "<leader>b",     actions.toggle_files,               { desc = "Toggle the file panel" } },
    --     { "n", "g<C-x>",        actions.cycle_layout,               { desc = "Cycle available layouts" } },
    --     { "n", "g?",            actions.help("file_history_panel"), { desc = "Open the help panel" } },
    --   },
    --   option_panel = {
    --     { "n", "<tab>", actions.select_entry,         { desc = "Change the current option" } },
    --     { "n", "q",     actions.close,                { desc = "Close the panel" } },
    --     { "n", "g?",    actions.help("option_panel"), { desc = "Open the help panel" } },
    --   },
    --   help_panel = {
    --     { "n", "q",     actions.close, { desc = "Close help menu" } },
    --     { "n", "<esc>", actions.close, { desc = "Close help menu" } },
    --   },
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
  local diffview = require("diffview")
  local diffview_lib = require("diffview.lib")

  -- Check if diffview is open
  local has_diffview = next(diffview_lib.views) ~= nil

  -- Check if fugitive buffer is open
  local fugitiveBuf = vim.fn.bufnr("fugitive://")
  local has_fugitive = fugitiveBuf >= 0 and vim.fn.bufwinnr(fugitiveBuf) >= 0

  if has_diffview then
    -- Close diffview (this will close the tab and any fugitive in it)
    vim.cmd("DiffviewClose")
  elseif has_fugitive then
    -- Close standalone fugitive buffer
    vim.cmd("bunload " .. fugitiveBuf)
  else
    -- Open combined interface
    diffview.open()
    -- diffview.emit("toggle_files")
    -- vim.cmd("Git")
  end
end

function M.browseCurrentLine()
  local linenum = vim.api.nvim_win_get_cursor(0)
  vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
