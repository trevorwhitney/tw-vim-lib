local M = {}

local function setOptions()
  local set = vim.opt

  set.autoindent = true
  set.autoread = true
  set.autowrite = true
  set.autowriteall = true
  set.breakindent = true
  set.expandtab = true -- Use soft tabs
  set.incsearch = true
  set.wrap = false    -- No wrapping
  set.number = true   -- Line numbers
  set.splitright = true
  set.splitbelow = true
  set.undofile = true
  set.showmatch = true                        -- Show matching brackets/braces
  set.smarttab = true                         -- Use shiftwidth to tab at line beginning
  set.showmode = false                        -- mode shown through pretty bottom bar instead

  set.backspace = { "indent", "eol", "start" } -- Let backspace work over anything.
  set.ignorecase = true                       -- ignore case only when search term is all lowercase
  set.smartcase = true                        -- ignore case only when search term is all lowercase
  set.mouse = "a"                             -- enable mouse in all modes
  set.scrolloff = 5
  set.shiftwidth = 2                          -- Width of autoindent
  set.tabstop = 2                             -- Tab settings
  set.tags:prepend("./.git/tags")
  set.undodir = vim.env.HOME .. "/.vim/undodir"
  set.encoding = "utf-8"
  set.spelllang = "en_us"
  set.guifont = "JetBrainsMono Nerd Font"

  -- TextEdit might fail if hidden is not set.
  set.hidden = true

  -- Some servers have issues with backup files, see #649.
  set.backup = false
  set.writebackup = true

  -- Give more space for displaying messages.
  set.cmdheight = 2

  -- Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
  -- delays and poor user experience.
  set.updatetime = 300

  -- Don't pass messages to |ins-completion-menu|.
  set.shortmess:append("c")

  -- Open diffs vertically
  set.diffopt = "vertical"
  set.clipboard = "unnamedplus"

  -- folding
  set.foldmethod = "expr" -- fold based on treesitter
  set.foldexpr = "nvim_treesitter#foldexpr()"
  set.foldenable = false -- dont fold by default
  set.foldopen = "insert" -- open folds when inserted into

  -- Auto completion
  set.completeopt = { "menu", "menuone", "longest" }
  set.wildignore:append({ "*\\tmp\\*", "*.swp", "*.swo", "*.zip", ".git", ".cabal-sandbox" })
  set.wildmode = { "longest", "list", "full" }
  set.wildmenu = true
  set.completeopt:append("longest")

  -- Directories
  set.directory = { vim.env.HOME .. "/.vim/tmp" }
  set.backupdir = { vim.env.HOME .. "/.vim/tmp" }

  -- Switchbuf
  set.switchbuf = { "useopen", "uselast" }

  -- Always show the signcolumn, otherwise it would shift the text each time
  -- diagnostics appear/become resolved.
  if vim.fn.has("patch-8.1.1564") then
    -- Recently vim can merge signcolumn and number column into one
    set.signcolumn = "number"
  else
    set.signcolumn = "auto:2"
  end

  -- disable python2 provider
  vim.g["loaded_python_provider"] = 0
  vim.g["python3_host_prog"] = "/usr/local/bin/python"

  -- diable perl provider
  vim.g["loaded_perl_provider"] = 0

  -- disable default markdown textobj mappings
  vim.g["textobj_markdown_no_default_key_mappings"] = 1

  -- need to disable this or it messes with git index buffers
  vim.g["jsonnet_fmt_on_save"] = 0

  -- vim visual multi
  -- press n/N to get next/previous occurrence
  -- press [/] to select next/previous cursor
  -- press q to skip current and get next occurrence
  -- press Q to remove current cursor/selection
  -- start insert mode with i,a,I,A
  vim.g["VM_maps"] = {
    ["Find Under"] = "<C-d>",       -- replace C-n
    ["Find Subword Under"] = "<C-d>", -- replace visual C-n
  }
end

function M.setup()
  setOptions()
end

return M
