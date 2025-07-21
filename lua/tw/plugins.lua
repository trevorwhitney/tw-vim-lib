Packer = {}

local function installNativeLsp(use)
  use("neovim/nvim-lspconfig") -- Collection of configurations for built-in LSP client
  use({
    "ray-x/navigator.lua",
    requires = {
      { "ray-x/guihua.lua",     run = "cd lua/fzy && make" },
      { "neovim/nvim-lspconfig" },
    },
  })

  use("fatih/vim-go")
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
  })

  use({
    "theHamsta/nvim-dap-virtual-text",
    requires = { "mfussenegger/nvim-dap" },
    config = function()
      require("nvim-dap-virtual-text").setup({
        commented = true,
        virt_text_pos = "eol",
      })
    end,
  })

  use({
    "rcarriga/nvim-dap-ui",
    requires = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
  })

  use({ "mxsdev/nvim-dap-vscode-js", requires = { "mfussenegger/nvim-dap" } })
  use({
    "microsoft/vscode-js-debug",
    opt = true,
    run = "npm install --legacy-peer-deps --no-save && npx gulp vsDebugServerBundle && mv dist out",
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

  use({
    "L3MON4D3/LuaSnip",
    requires = {
      "rafamadriz/friendly-snippets",
    },
  })
end

local function installTreesitter(use)
  use("nvim-treesitter/nvim-treesitter")
  use("nvim-treesitter/nvim-treesitter-textobjects") -- Additional textobjects for treesitter
  use("nvim-treesitter/nvim-treesitter-context")
  use('nvim-telescope/telescope-ui-select.nvim')
end

local function installTesting(use)
  use({
    "vim-test/vim-test",
    requires = {
      { "tpope/vim-dispatch" },
    },
  })
end

local function installUI(use)
  -- color schemes
  use({ "trevorwhitney/solarized.nvim" })
  use({ "trevorwhitney/flexoki-neovim", as = "flexoki", branch = "enable-more-plugins" })
  -- use({ "kepano/flexoki-neovim", as = "flexoki" })
  use({
    "neanias/everforest-nvim",
    -- Optional; default configuration will be used if setup isn't called.
    config = function()
      require("everforest").setup()
    end,
  })
end

local function installAiTools(use)
  -- use("zbirenbaum/copilot.lua")
  use({
    "supermaven-inc/supermaven-nvim",
    requires = {
      "onsails/lspkind.nvim"
    }
  })
  -- taken from avante dependencies
  use({ 'MeanderingProgrammer/render-markdown.nvim' })
  use({ 'HakonHarnes/img-clip.nvim' })
end
function Packer.install(use)
  local packer = require("packer")
  packer.util = require('packer.util')
  packer.init({
    max_jobs = 5,
  })

  packer.startup(function()
    use("wbthomason/packer.nvim")

    use({
      "christoomey/vim-tmux-navigator",
      config = function()
        vim.g["tmux_navigator_no_mappings"] = 1
      end
    })    -- C-<h,j,k,l> seamlessly switches between vim and tmux splits
    use("coachshea/vim-textobj-markdown")
    use({ "folke/which-key.nvim", requires = "echasnovski/mini.nvim" })
    use("google/vim-jsonnet")
    use("junegunn/vader.vim")
    use("kana/vim-textobj-entire")
    use("kana/vim-textobj-user")
    use({ "mg979/vim-visual-multi", branch = "master" }) -- multi-cursor
    use("pedrohdz/vim-yaml-folds")
    use("tpope/vim-abolish")
    use({
      "tpope/vim-dispatch",
      config = function()
        vim.g["dispatch_no_maps"] = 1
      end,
    })

    use("tpope/vim-eunuch")
    use({ "tpope/vim-fugitive", requires = "tpope/vim-rhubarb" })
    use("tpope/vim-repeat")
    use("tpope/vim-rsi")
    use("tpope/vim-surround")
    use("fladson/vim-kitty")
    use("chrisbra/colorizer")
    use("andymass/vim-matchup") -- show matching pairs
    use({
      "windwp/nvim-autopairs",
      config = function()
        require("nvim-autopairs").setup({})
      end,
    }) -- automatically insert closing brackets
    use({
      "kyazdani42/nvim-tree.lua",
      requires = {
        "kyazdani42/nvim-web-devicons",
      },
    })
    use({
      "nvim-lualine/lualine.nvim",
      requires = { "kyazdani42/nvim-web-devicons", opt = true },
    })

    use("towolf/vim-helm")
    use("rfratto/vim-river")
    use("mfussenegger/nvim-jdtls")

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

    use("chrisbra/NrrwRgn")

    use("gabrielpoca/replacer.nvim")
    use("romainl/vim-qf")

    use({
      "lewis6991/gitsigns.nvim",
      requires = { "nvim-lua/plenary.nvim" },
    })

    use("stevearc/conform.nvim")

    use({ "folke/trouble.nvim", requires = { "nvim-tree/nvim-web-devicons" } })

    use({
      "stevearc/aerial.nvim",
      config = function()
        local wk = require("which-key")
        require("aerial").setup({
          layout = {
            max_with = { 50, 0.2 },
          },
          on_attach = function(_)
            local keymap = {
              -- Jump forwards/backwards with '{' and '}'
              { "{", "<cmd>AerialPrev<CR>", desc = "Jump to previous symbol", nowait = false, remap = false },
              { "}", "<cmd>AerialNext<CR>", desc = "Jump to next symbol",     nowait = false, remap = false },
            }

            wk.add(keymap)
          end,
        })
      end
    })
    use("dstein64/vim-win")
    use("ii14/neorepl.nvim")
    use("grafana/vim-alloy")
    installNativeLsp(use)
    installTelescope(use)
    installDap(use)
    installNvimCmp(use)
    installTreesitter(use)
    installTesting(use)
    installUI(use)
    installAiTools(use)
  end)
end

return Packer
