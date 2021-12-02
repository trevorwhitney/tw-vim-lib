local Packer = {}

local function installNativeLsp(use)
	use("L3MON4D3/LuaSnip") -- Snippets plugin
	use("hrsh7th/cmp-nvim-lsp")
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
			})
		end,
	})
end

local function installTelescope(use)
	use({
		"nvim-telescope/telescope.nvim",
		requires = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-live-grep-raw.nvim",
		},
	})
	use({ "nvim-telescope/telescope-fzf-native.nvim", run = "make" })
end

function Packer.install(use)
	require("packer").startup(function()
		-- fix
		use("trevorwhitney/tw-vim-lib")
		use("wbthomason/packer.nvim")
		use({
			"nvim-treesitter/nvim-treesitter",
			config = function()
				local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
				parser_config.bash.used_by = { "zsh" }

				require("nvim-treesitter.configs").setup({
					ensure_installed = {
						"bash",
						"go",
						"lua",
						"nix",
					}, -- one of "all", "maintained" (parsers with maintainers), or a list of languages
					sync_install = false, -- install languages synchronously (only applied to `ensure_installed`)
					ignore_install = { "haskell" }, -- List of parsers to ignore installing
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
		-- end fix
		use("AndrewRadev/bufferize.vim") -- open the output of any command in a buffer
		use({ "benmills/vimux-golang", requires = "benmills/vimux" }) -- open commands in tmux split
		use("christoomey/vim-tmux-navigator") -- C-<h,j,k,l> seamlessly switches between vim and tmux splits
		use("coachshea/vim-textobj-markdown")
		use("easymotion/vim-easymotion")
		use("fatih/vim-go")
		use("folke/which-key.nvim")
		use("google/vim-jsonnet")
		use("junegunn/vader.vim")
		use("jvirtanen/vim-hcl")
		use("kana/vim-textobj-entire")
		use("kana/vim-textobj-user")
		use("machakann/vim-highlightedyank")
		use({ "mg979/vim-visual-multi", branch = "master" }) -- multi-cursor
		-- use("nvim-treesitter/nvim-treesitter") -- Highlight, edit, and navigate code using a fast incremental parsing library
		use("nvim-treesitter/nvim-treesitter-textobjects") -- Additional textobjects for treesitter
		use("pedrohdz/vim-yaml-folds")
		use("roxma/vim-tmux-clipboard")
		use("sebdah/vim-delve")
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

		-- recently added
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
			config = function()
				require("nvim-tree").setup({})
			end,
		})
		use({
			"nvim-lualine/lualine.nvim",
			config = function()
				require("lualine").setup({ options = { theme = "solarized" } })
			end,
			requires = { "kyazdani42/nvim-web-devicons", opt = true },
		})

		-- TODO: key mappings on dashboard are not all correct
		use({
			"glepnir/dashboard-nvim",
			config = function()
				vim.g["dashboard_default_executive"] = "telescope"
				vim.g["dashboard_custom_header"] = {
					" ███╗   ██╗ ███████╗ ██████╗  ██╗   ██╗ ██╗ ███╗   ███╗",
					" ████╗  ██║ ██╔════╝██╔═══██╗ ██║   ██║ ██║ ████╗ ████║",
					" ██╔██╗ ██║ █████╗  ██║   ██║ ██║   ██║ ██║ ██╔████╔██║",
					" ██║╚██╗██║ ██╔══╝  ██║   ██║ ╚██╗ ██╔╝ ██║ ██║╚██╔╝██║",
					" ██║ ╚████║ ███████╗╚██████╔╝  ╚████╔╝  ██║ ██║ ╚═╝ ██║",
					" ╚═╝  ╚═══╝ ╚══════╝ ╚═════╝    ╚═══╝   ╚═╝ ╚═╝     ╚═╝",
				}
			end,
		})

		use({
			"ahmedkhalf/project.nvim",
			config = function()
				require("project_nvim").setup({})
			end,
		})

		use({
			"folke/trouble.nvim",
			requires = "kyazdani42/nvim-web-devicons",
			config = function()
				require("trouble").setup({})
			end,
		})

		installNativeLsp(use)

		installTelescope(use)
	end)
end

return Packer
