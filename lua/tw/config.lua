function setup()
  local set = vim.opt

  set.autoindent = true
  set.autoread = true
  set.autowrite = true
  set.autowriteall = true
  set.expandtab = true -- Use soft tabs
  set.incsearch = true
  set.nowrap = true -- No wrapping
  set.number = true -- Line numbers
  set.splitright = true
  set.undofile = true
  set.showmatch = true -- Show matching brackets/braces
  set.smarttab = true -- Use shiftwidth to tab at line beginning

  set.backspace = {'indent', 'eol', 'start'}  -- Let backspace work over anything.
  set.ignorecase = 'smartcase' -- ignore case only when search term is all lowercase
  set.mouse = 'a' -- enable mouse in all modes
  set.omnifunc = vim.fn['syntaxcomplete#Complete']
  set.scrolloff = 5
  set.shiftwidth = 2 -- Width of autoindent
  set.switchbuf = 'useopen'
  set.tabstop = 2 -- Tab settings
  set.tags ^= './.git/tags'
  set.undodir = vim.env.HOME .. '/.vim/undodir'
  set.encoding = 'utf-8'

  -- TextEdit might fail if hidden is not set.
  set.hidden = true

  -- Some servers have issues with backup files, see #649.
  set.nobackup = true
  set.nowritebackup = true

  -- Give more space for displaying messages.
  set cmdheight=2

  " Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
  " delays and poor user experience.
  set updatetime=300

  " Don't pass messages to |ins-completion-menu|.
  set shortmess+=c

  " Open diffs vertically
  set diffopt=vertical

  " disable python2 provider
  let g:loaded_python_provider = 0
  let g:python3_host_prog = '/usr/bin/python3'

  require('nvim-treesitter.configs').setup {
    ensure_installed = {
      "bash",
      "c",
      "go",
      "gomod",
      "java",
      "javascript",
      "json",
      "kotlin",
      "lua",
      "nix",
      "python",
      "typescript",
      "css",
      "rust",
      "toml",
      "yaml",
      "vim",
    }, -- one of "all", "maintained" (parsers with maintainers), or a list of languages
    sync_install = false, -- install languages synchronously (only applied to `ensure_installed`)
    ignore_install = { "haskell" }, -- List of parsers to ignore installing
    highlight = {
      enable = true,              -- false will disable the whole extension
      -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
      -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
      -- Using this option may slow down your editor, and you may see some duplicate highlights.
      -- Instead of true it can also be a list of languages
      additional_vim_regex_highlighting = false,
    },
  }

  require('which-key').setup {
    window = {
      border = "single"
    }
  }
end
