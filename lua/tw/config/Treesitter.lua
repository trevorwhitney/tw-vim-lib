local M = {}

local ensure_installed = {
  "bash",
  "bibtex",
  "c",
  "c_sharp",
  "clojure",
  "cmake",
  "comment",
  "commonlisp",
  "cpp",
  "css",
  "dockerfile",
  "dot",
  "elixir",
  "erlang",
  "fish",
  "go",
  "godot_resource",
  "gomod",
  "gowork",
  "graphql",
  "hcl",
  "hjson",
  "hocon",
  "html",
  "http",
  "java",
  "javascript",
  "jsdoc",
  "json",
  "json5",
  "jsonc",
  "jsonnet",
  "julia",
  "kotlin",
  "latex",
  "llvm",
  "lua",
  "make",
  "markdown",
  "nix",
  "perl",
  "php",
  "python",
  "ql",
  "query",
  "r",
  "regex",
  "ruby",
  "rust",
  "scala",
  "scheme",
  "scss",
  "todotxt",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "wgsl",
  "yaml",
}

local function configure()
  require("nvim-treesitter.configs").setup({
    ensure_installed = ensure_installed,
    sync_install = false, -- install languages synchronously (only applied to `ensure_installed`)
    ignore_install = { "haskell", "phpdoc" }, -- List of parsers to ignore installing
    highlight = {
      enable = true, -- false will disable the whole extension
      -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
      -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
      -- Using this option may slow down your editor, and you may see some duplicate highlights.
      -- Instead of true it can also be a list of languages
      additional_vim_regex_highlighting = false,
    },
  })
end

function M.setup()
  configure()
end

return M
