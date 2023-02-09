Packer = {}

local function installNativeLsp(use)
  use("neovim/nvim-lspconfig") -- Collection of configurations for built-in LSP client
  use({ "jose-elias-alvarez/null-ls.nvim", requires = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" } })
  use({
    "lewis6991/gitsigns.nvim",
    requires = { "nvim-lua/plenary.nvim" },
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
  use({
    "mfussenegger/nvim-dap",
    wants = { "nvim-dap-virtual-text", "nvim-dap-ui" },
    requires = {
      "nvim-telescope/telescope-dap.nvim",
    },
  })

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
      require("nvim-dap-virtual-text").setup({
        commented = true,
      })
    end,
  })

  use({
    "rcarriga/nvim-dap-ui",
    requires = { "mfussenegger/nvim-dap" },
  })
end

local function installNvimCmp(use)
  use({
    "hrsh7th/nvim-cmp",
    requires = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lua",
      "hrsh7th/cmp-calc",
      "hrsh7th/cmp-emoji",
      "hrsh7th/cmp-omni",
      "hrsh7th/cmp-cmdline",

      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",

      "rafamadriz/friendly-snippets",
    },
    config = function()
      require("luasnip.loaders.from_lua").lazy_load()
      require("luasnip.loaders.from_vscode").lazy_load()
    end,
  })
end

function Packer.install(use)
  require("packer").startup(function()
    use("trevorwhitney/tw-vim-lib")
    use("wbthomason/packer.nvim")

    use("nvim-treesitter/nvim-treesitter")
    use("nvim-treesitter/nvim-treesitter-textobjects") -- Additional textobjects for treesitter

    -- Show current function at the top of the screen when function does not fit in screen
    use({
      "romgrk/nvim-treesitter-context",
      config = function()
        require("treesitter-context").setup({
          enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
          throttle = true, -- Throttles plugin updates (may improve performance)
          max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
          patterns = { -- Match patterns for TS nodes. These get wrapped to match at word boundaries.
            -- For all filetypes
            -- Note that setting an entry here replaces all other patterns for this entry.
            -- By setting the 'default' entry below, you can control which nodes you want to
            -- appear in the context window.
            default = {
              "class",
              "function",
              "method",
            },
          },
        })
      end,
    })

    use("AndrewRadev/bufferize.vim") -- open the output of any command in a buffer
    use({ "benmills/vimux-golang", requires = "benmills/vimux" }) -- open commands in tmux split
    use("christoomey/vim-tmux-navigator") -- C-<h,j,k,l> seamlessly switches between vim and tmux splits
    use("coachshea/vim-textobj-markdown")
    use("easymotion/vim-easymotion")
    use({
      "fatih/vim-go",
      config = function()
        vim.g["go_code_completion_enabled"] = 0
        vim.g["go_def_mapping_enabled"] = 0
        vim.g["go_build_tags"] = "e2e_gem,requires_docker"
        vim.g["go_textobj_enabled"] = 0
        vim.g["go_gopls_enabled"] = 0
      end,
    })
    use("folke/which-key.nvim")
    use("google/vim-jsonnet")
    use("junegunn/vader.vim")
    -- use("jvirtanen/vim-hcl")
    use("kana/vim-textobj-entire")
    use("kana/vim-textobj-user")
    use("machakann/vim-highlightedyank")
    use({ "mg979/vim-visual-multi", branch = "master" }) -- multi-cursor
    use("pedrohdz/vim-yaml-folds")
    -- this broke on stem
    -- use("roxma/vim-tmux-clipboard")
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
    use("fladson/vim-kitty")
    use("chrisbra/colorizer")

    -- color schemes
    use({ "trevorwhitney/solarized.nvim", branch = "less-red" })
    use("EdenEast/nightfox.nvim")
    use({
      "mcchrish/zenbones.nvim",
      -- Optionally install Lush. Allows for more configuration or extending the colorscheme
      -- If you don't want to install lush, make sure to set g:zenbones_compat = 1
      -- In Vim, compat mode is turned on as Lush only works in Neovim.
      requires = "rktjmp/lush.nvim",
    })

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
    use({
      "milkypostman/vim-togglelist",
      config = function()
        vim.g["toggle_list_no_mappings"] = 1
      end,
    })

    use("mfussenegger/nvim-jdtls")

    use("github/copilot.vim")

    use({
      "ThePrimeagen/refactoring.nvim",
      requires = {
        { "nvim-lua/plenary.nvim" },
        { "nvim-treesitter/nvim-treesitter" },
      },
      config = function()
        require("refactoring").setup({})
      end,
    })

    installNativeLsp(use)

    installTelescope(use)

    installDap(use)

    installNvimCmp(use)
  end)
end

return Packer
