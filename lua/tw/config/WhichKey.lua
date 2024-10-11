local M = {}

local function mapKeys(wk)
  local trouble = require("trouble")
  local format = require("tw.config.Formatting").format
  local async = require("plenary.async")
  local telescope = require("telescope")

  local keymap = {
    { "<leader>*",  "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>", desc = "Find Grep (Current Word)", nowait = false, remap = false },
    { "<leader>D",  "<cmd>Lspsaga show_line_diagnostics<cr>",                                                                                  desc = "Line Diagnostics",         nowait = false, remap = false },
    { "<leader>F",  "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>",                                            desc = "Find Grep",                nowait = false, remap = false },
    { "<leader>R",  "<cmd>Telescope resume<cr>",                                                                                               desc = "Resume Find",              nowait = false, remap = false },
    { "<leader>\\", "<cmd>NvimTreeToggle<cr>",                                                                                                 desc = "NvimTree",                 nowait = false, remap = false },
    { "<leader>b",  "<cmd>Telescope buffers<cr>",                                                                                              desc = "Find Buffer",              nowait = false, remap = false },
    { "<leader>c",  group = "Copilot",                                                                                                         nowait = false,                    remap = false },
    { "<leader>cc", "<cmd>CopilotChat<cr>",                                                                                                    desc = "Chat",                     nowait = false, remap = false },
    { "<leader>f",  "<cmd>Telescope git_files<cr>",                                                                                            desc = "Find File (Git)",          nowait = false, remap = false },
    { "<leader>i",  group = "Config",                                                                                                          nowait = false,                    remap = false },
    {
      "<leader>ic",
      function()
        require("tw.config.Appearance").switch_colors()
      end,
      desc = "Reset Colors (to System)",
      nowait = false,
      remap = false
    },
    {
      "<leader>id",
      function()
        vim.opt.background = "dark"
        vim.cmd("colorscheme everforest")
        require("lualine").setup({ options = { theme = "everforest" } })
      end,
      desc = "Dark Mode",
      nowait = false,
      remap = false
    },
    {
      "<leader>il",
      function()
        vim.opt.background = "light"
        vim.cmd("colorscheme everforest")
        require("lualine").setup({ options = { theme = "everforest" } })
      end,
      desc = "Light Mode",
      nowait = false,
      remap = false
    },
    { "<leader>p",   group = "Print",                                                         nowait = false,                    remap = false },
    { "<leader>pc",  "<cmd>lua require('refactoring').debug.cleanup()<CR>",                   desc = "Cleanup Print Statements", nowait = false, remap = false },
    { "<leader>pd",  "<cmd>lua require('refactoring').debug.printf({below = false})<CR>",     desc = "Print Debug Line",         nowait = false, remap = false },
    { "<leader>pv",  "<cmd>lua require('refactoring').debug.print_var()<CR>",                 desc = "Print Var",                nowait = false, remap = false },
    { "<leader>r",   group = "Refactor",                                                      nowait = false,                    remap = false },
    { "<leader>rbf", "<cmd>lua require('refactoring').refactor('Extract Block To File')<CR>", desc = "Extract Block to File",    nowait = false, remap = false },
    { "<leader>rbl", "<cmd>lua require('refactoring').refactor('Extract Block')<CR>",         desc = "Extract Block",            nowait = false, remap = false },
    { "<leader>ri",  "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>",       desc = "Inline Variable",          nowait = false, remap = false },
    { "<leader>rp",  "<cmd>lua require('replacer').run()<cr>",                                desc = "Replacer",                 nowait = false, remap = false },
    { "<leader>rr",  "<cmd>lua require('telescope').extensions.refactoring.refactors()<CR>",  desc = "Refactor Menu",            nowait = false, remap = false },
    { "<leader>s",   "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",                      desc = "Find Symbol",              nowait = false, remap = false },
    { "<leader>t",   group = "Test",                                                          nowait = false,                    remap = false },
    { "<leader>tO",  ":Copen!<cr>",                                                           desc = "Verbose Test Output",      nowait = false, remap = false },
    { "<leader>tf",  ":w<cr> :TestFile<cr>",                                                  desc = "Test File",                nowait = false, remap = false },
    { "<leader>tl",  ":w<cr> :TestLast<cr>",                                                  desc = "Test Last",                nowait = false, remap = false },
    { "<leader>to",  ":Copen<cr>",                                                            desc = "Test Output",              nowait = false, remap = false },
    { "<leader>tt",  ":w<cr> :TestNearest<cr>",                                               desc = "Test Nearest",             nowait = false, remap = false },
    { "<leader>tv",  ":TestVisit<cr>",                                                        desc = "Open Last Run Test",       nowait = false, remap = false },
    { "<leader>|",   "<cmd>NvimTreeFindFile<cr>",                                             desc = "NvimTree (Current File)",  nowait = false, remap = false },


    { "[T",          ":tabfirst<cr>",                                                         desc = "First Tab",                nowait = true,  remap = false },
    { "]T",          ":tablast<cr>",                                                          desc = "Last Tab",                 nowait = true,  remap = false },
    { "[b",          ":bprevious<cr>",                                                        desc = "Previous Buffer",          nowait = true,  remap = false },
    { "]b",          ":bnext<cr>",                                                            desc = "Next Buffer",              nowait = true,  remap = false },
    {
      "[d",
      function()
        if not trouble.is_open() then
          trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
        end

        trouble.previous({ skip_groups = true, jump = true })
      end,
      desc = "Previous Diagnostic",
      nowait = true,
      remap = false
    },
    {
      "]d",
      function()
        if not trouble.is_open() then
          trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
        end

        trouble.next({ skip_groups = true, jump = true })
      end,
      desc = "Next Diagnostic",
      nowait = true,
      remap = false
    },
    {
      "[q",
      function()
        if not trouble.is_open() then
          trouble.toggle("quickfix")
        end

        trouble.previous({ skip_groups = true, jump = true })
      end,
      desc = "Previous Quickfix",
      nowait = true,
      remap = false
    },
    {
      "]q",
      function()
        if not trouble.is_open() then
          trouble.toggle("quickfix")
        end

        trouble.next({ skip_groups = true, jump = true })
      end,
      desc = "Next Quickfix",
      nowait = true,
      remap = false
    },
    { "]t", ":tabnext<cr>",     desc = "Next Tab",     nowait = true, remap = false },
    { "[t", ":tabprevious<cr>", desc = "Previous Tab", nowait = true, remap = false },

    { "\\", group = "Windows",  nowait = true,         remap = false },
    {
      "\\D",
      function()
        trouble.toggle("diagnostics")
      end,
      desc = "Workspace Diagnostics",
      nowait = true,
      remap = false
    },
    {
      "\\d",
      function()
        trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
      end,
      desc = "Document Diagnostics",
      nowait = true,
      remap = false
    },
    { "\\O", "<cmd>AerialToggle!<cr>",             desc = "Toggle Outline",         nowait = true, remap = false },
    { "\\S", "<cmd>Telescope git_status<cr>",      desc = "Git Status (Telescope)", nowait = true, remap = false },
    { "\\b", "<cmd>Telescope git_branches<cr>",    desc = "Branches",               nowait = true, remap = false },
    { "\\c", "<cmd>DapToggleConsole<cr>",          desc = "Dap Console",            nowait = true, remap = false },
    { "\\j", "<cmd>Telescope jumplist<cr>",        desc = "Jump List",              nowait = true, remap = false },
    { "\\l", "<cmd>call ToggleLocationList()<cr>", desc = "Location List",          nowait = true, remap = false },
    { "\\m", "<cmd>Telescope marks<cr>",           desc = "Marks",                  nowait = true, remap = false },
    {
      "\\o",
      function()
        telescope.extensions.aerial.aerial()
      end,
      desc = "Outline",
      nowait = true,
      remap = false,
    },
    { "\\p", "<cmd>pclose<cr>",                                         desc = "Close Preview", nowait = true, remap = false },
    {
      "\\q",
      function()
        trouble.toggle("quickfix")
      end,
      desc = "Quickfix",
      nowait = true,
      remap = false
    },
    {
      "\\r",
      function()
        -- get current buffer and window
        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()

        -- create a new split for the repl
        vim.cmd('split')

        -- spawn repl and set the context to our buffer
        require('neorepl').new({
          lang = 'lua',
          buffer = buf,
          window = win,
        })
        -- resize repl window and make it fixed height
        vim.cmd('resize 10 | setl winfixheight')
      end,
      desc = "Neovim REPL",
      nowait = true,
      remap = false
    },
    { "\\s", "<cmd>lua require('tw.config.Git').toggleGitStatus()<cr>", desc = "Git Status",    nowait = true, remap = false },

    {
      mode = { "v" },
      { "<leader>*",  "\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",            desc = "Search Current Selection", nowait = false, remap = false },
      -- { "<leader>c",  group = "Copilot",                                                                                        nowait = false,                    remap = false },
      -- { "<leader>cc", "<cmd>CopilotChat<cr>",                                                                                   desc = "Chat",                     nowait = false, remap = false },
      -- { "<leader>cd", "<cmd>CopilotChatDocs<cr>",                                                                               desc = "Docs",                     nowait = false, remap = false },
      -- { "<leader>ce", "<cmd>CopilotChatExplain<cr>",                                                                            desc = "Explain",                  nowait = false, remap = false },
      -- { "<leader>cf", "<cmd>CopilotChatFix<cr>",                                                                                desc = "Fix",                      nowait = false, remap = false },
      -- { "<leader>co", "<cmd>CopilotChatOptimize<cr>",                                                                           desc = "Optimize",                 nowait = false, remap = false },
      -- { "<leader>ct", "<cmd>CopilotChatTests<cr>",                                                                              desc = "Tests",                    nowait = false, remap = false },
      { "<leader>p",  group = "Print",                                                                                          nowait = false,                    remap = false },
      { "<leader>pv", "<cmd>lua require('refactoring').debug.print_var()<CR>",                                                  desc = "Print Var",                nowait = false, remap = false },
      { "<leader>r",  group = "Refactor",                                                                                       nowait = false,                    remap = false },
      { "<leader>re", "<cmd>lua require('refactoring').refactor('Extract Function')<CR>",                                       desc = "Extract Function",         nowait = false, remap = false },
      { "<leader>rf", "<cmd>lua require('refactoring').refactor('Extract Function To File')<CR>",                               desc = "Extract Function To File", nowait = false, remap = false },
      { "<leader>ri", "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>",                                        desc = "Inline Variable",          nowait = false, remap = false },
      { "<leader>rv", "<cmd>lua require('refactoring').refactor('Extract Variable')<CR>",                                       desc = "Extract Variable",         nowait = false, remap = false },
      { "<leader>s",  "\"sy:TelescopeDynamicWorkspaceSymbol <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>", desc = "Search Current Symbol",    nowait = false, remap = false },
      { "<leader>z",  ":'<,'>sort<cr>",                                                                                         desc = "sort",                     nowait = false, remap = false },
    },
    -- Formatting
    {
      mode = { "v", "x" },
      {
        "<leader>=",
        function()
          vim.cmd("update")
          require('conform').format({ async = false, lsp_format = "first" })
        end,
        desc = "Format",
        nowait = true,
        remap = false
      },
    },
    {
      mode = { "n" },
      {
        "<leader>=",
        function()
          vim.cmd("update")
          format()
        end,
        desc = "Format",
        nowait = true,
        remap = false
      },
    },
  }

  wk.add(keymap)

  vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
  vim.cmd(
    "command! -nargs=* TelescopeDynamicWorkspaceSymbol call v:lua.require('tw.telescope').dynamic_workspace_symbols(<q-args>)"
  )
end

local function vimMappings()
  local cmd = vim.cmd
  cmd.ca("Qa", "qa")
  cmd.ca("QA", "qa")
  cmd.ca("q", "q")
  cmd.ca("W", "w")
  cmd.ca("WQ", "wq")
  cmd.ca("Wq", "wq")

  local api = vim.api
  api.nvim_create_user_command("Qa", ":qa", { bang = true, nargs = 0 })
  api.nvim_create_user_command("QA", ":qa", { bang = true, nargs = 0 })
  api.nvim_create_user_command("Q", ":q", { bang = true, nargs = 0 })
  api.nvim_create_user_command("Wq", ":wq", { bang = true, nargs = 0 })
  api.nvim_create_user_command("WQ", ":wq", { bang = true, nargs = 0 })
  api.nvim_create_user_command("W", ":w", { bang = true, nargs = 0 })

  local keymap = vim.keymap
  keymap.set("n", "<C-q>", "<Nop>", { noremap = true })
  keymap.set("x", "il", "g_o^", { noremap = true })
  keymap.set("o", "il", ":normal vil<cr>", { noremap = true })
  keymap.set("x", "al", "$o^", { noremap = true })
  keymap.set("o", "al", ":normal val<cr>", { noremap = true })

  keymap.set("i", "jj", "<Esc>", { noremap = true, nowait = true })
  keymap.set("c", "w!!", ":w !sudo tee > /dev/null %")

  keymap.set("i", "<C-o>", "<C-x><C-o>", { noremap = true })

  keymap.set("n", "<C-J>", "<C-W><C-J>", { noremap = true })
  keymap.set("n", "<C-K>", "<C-W><C-K>", { noremap = true })
  keymap.set("n", "<C-L>", "<C-W><C-L>", { noremap = true })
  keymap.set("n", "<C-H>", "<C-W><C-H>", { noremap = true })
  keymap.set("n", "<C-w>q", ":window close<cr>", { noremap = true })

  -- ====== Readline / RSI =======
  keymap.set("i", "<c-k>", "<c-o>D", { noremap = true })
  keymap.set("c", "<c-k>", "<c-\\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<cr>", { noremap = true })
end

function M.setup()
  local which_key = require("which-key")
  which_key.setup({
    win = {
      border = "single",
    },
  })

  mapKeys(which_key)
  vimMappings()
end

return M
