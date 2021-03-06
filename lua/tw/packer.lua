Packer = {}

local function installNativeLsp(use)
  use("L3MON4D3/LuaSnip") -- Snippets plugin
  use("hrsh7th/cmp-nvim-lsp")
  -- use("hrsh7th/cmp-omni")
  use("hrsh7th/nvim-cmp") -- Autocompletion plugin
  use("neovim/nvim-lspconfig") -- Collection of configurations for built-in LSP client
  use("rafamadriz/friendly-snippets")
  use("saadparwaiz1/cmp_luasnip")
  use({ "jose-elias-alvarez/null-ls.nvim", requires = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" } })
  use({
    "lewis6991/gitsigns.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
      require("gitsigns").setup({
        current_line_blame = true,
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map("n", "]c", "&diff ? ']c' : '<cmd>Gitsigns next_hunk<CR>'", { expr = true })
          map("n", "[c", "&diff ? '[c' : '<cmd>Gitsigns prev_hunk<CR>'", { expr = true })

          -- Actions
          map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>")
          map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>")
          map("n", "<leader>hS", gs.stage_buffer)
          map("n", "<leader>hu", gs.undo_stage_hunk)
          map("n", "<leader>hR", gs.reset_buffer)
          map("n", "<leader>hp", gs.preview_hunk)
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end)
          map("n", "<leader>tb", gs.toggle_current_line_blame)
          map("n", "<leader>hd", gs.diffthis)
          map("n", "<leader>hD", function()
            gs.diffthis("~")
          end)
          map("n", "<leader>td", gs.toggle_deleted)

          -- Text object
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")
        end,
      })
    end,
  })
end

local function installTelescope(use)
  use({
    "nvim-telescope/telescope.nvim",
    requires = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
  })
  use({ "nvim-telescope/telescope-fzf-native.nvim", run = "make" })
end

local function installDap(use)
  use("mfussenegger/nvim-dap")
  use({
    "leoluz/nvim-dap-go",
    requires = { "mfussenegger/nvim-dap" },
    config = function()
      require("dap-go").setup()
    end,
  })
  use({
    "theHamsta/nvim-dap-virtual-text",
    requires = { "mfussenegger/nvim-dap" },
    config = function()
      require("nvim-dap-virtual-text").setup()
    end,
  })
  use({
    "rcarriga/nvim-dap-ui",
    requires = { "mfussenegger/nvim-dap" },
  })
end

function Packer.install(use)
  require("packer").startup(function()
    use("trevorwhitney/tw-vim-lib")
    use("wbthomason/packer.nvim")

    use({
      "nvim-treesitter/nvim-treesitter",
      config = function()
        require("nvim-treesitter.configs").setup({
          ensure_installed = {
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
          },
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
      end,
    })

    use("AndrewRadev/bufferize.vim") -- open the output of any command in a buffer
    use({ "benmills/vimux-golang", requires = "benmills/vimux" }) -- open commands in tmux split
    use("christoomey/vim-tmux-navigator") -- C-<h,j,k,l> seamlessly switches between vim and tmux splits
    use("coachshea/vim-textobj-markdown")
    use("easymotion/vim-easymotion")
    use("fatih/vim-go")
    use("folke/which-key.nvim")
    use("google/vim-jsonnet")
    use("junegunn/vader.vim")
    -- use("jvirtanen/vim-hcl")
    use("kana/vim-textobj-entire")
    use("kana/vim-textobj-user")
    use("machakann/vim-highlightedyank")
    use({ "mg979/vim-visual-multi", branch = "master" }) -- multi-cursor
    use("nvim-treesitter/nvim-treesitter-textobjects") -- Additional textobjects for treesitter
    use("pedrohdz/vim-yaml-folds")
    -- this broke on stem
    -- use("roxma/vim-tmux-clipboard")
    use("shaunsingh/solarized.nvim")
    use("tommcdo/vim-exchange")
    use("tpope/vim-abolish")
    use("tpope/vim-commentary")
    use("tpope/vim-dispatch")
    use("tpope/vim-eunuch")
    use({ "tpope/vim-fugitive", requires = "tpope/vim-rhubarb" })
    use("tpope/vim-projectionist")
    use("tpope/vim-repeat")
    use("tpope/vim-rsi")
    use("tpope/vim-surround")
    use("tpope/vim-unimpaired")
    use("glepnir/dashboard-nvim")

    use("andymass/vim-matchup") -- show matching pairs
    use({
      "windwp/nvim-autopairs",
      config = function()
        require("nvim-autopairs").setup({})
      end,
    }) -- automatically insert closing brackets
    use({
      "kyazdani42/nvim-tree.lua",
      requires = "kyazdani42/nvim-web-devicons",
    })
    use({
      "nvim-lualine/lualine.nvim",
      config = function()
        require("lualine").setup({ options = { theme = "solarized" } })
      end,
      requires = { "kyazdani42/nvim-web-devicons", opt = true },
    })

    use({
      "ahmedkhalf/project.nvim",
      config = function()
        require("project_nvim").setup({})
      end,
    })

    use({
      "pwntester/octo.nvim",
      config = function()
        require("octo").setup()
      end,
    })

    use("towolf/vim-helm")
    use("milkypostman/vim-togglelist")

    use("mfussenegger/nvim-jdtls")

    installNativeLsp(use)

    installTelescope(use)

    installDap(use)
  end)
end

return Packer
