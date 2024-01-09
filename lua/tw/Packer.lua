Packer = {}

local function installNativeLsp(use)
	use("neovim/nvim-lspconfig") -- Collection of configurations for built-in LSP client
	use({ "jose-elias-alvarez/null-ls.nvim", requires = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" } })
	use({
		"nvimdev/lspsaga.nvim",
		after = "nvim-lspconfig",
		config = function()
			require("lspsaga").setup({
				ui = {
					code_action = "󰛨 ",
				},
				finder = {
					max_height = 0.8,
					left_width = 0.35,
					right_width = 0.55,
					methods = {
						tyd = "textDocument/typeDefinition",
					},
					keys = {
						toggle_or_open = "<CR>",
						vsplit = "<C-v>",
						split = "<C-x>",
						tabnew = "<C-t>",
						quit = { "q", "<Esc>" },
					},
				},
				lightbulb = {
					sign_priority = 5,
					virtual_text = false,
				},
				code_action = {
					keys = {
						quit = { "q", "<Esc>" },
					},
				},
				rename = {
					auto_save = true,
					keys = {
						quit = { "q", "<Esc>" },
					},
				},
				diagnostic = {
					keys = {
						quit = { "q", "<Esc>" },
					},
				},
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

	use({ "mxsdev/nvim-dap-vscode-js", requires = { "mfussenegger/nvim-dap" } })
	use({
		"microsoft/vscode-js-debug",
		opt = true,
		run = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out",
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
end

function Packer.install(use)
	require("packer").startup(function()
		use("wbthomason/packer.nvim")

		use({
			"benmills/vimux",
			config = function()
				vim.g["VimuxUseNearest"] = 0
			end,
		}) -- open commands in tmux split
		use({ "benmills/vimux-golang", requires = "benmills/vimux" }) -- open go commands in tmux split
		use("christoomey/vim-tmux-navigator") -- C-<h,j,k,l> seamlessly switches between vim and tmux splits
		use("coachshea/vim-textobj-markdown")
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
		use("kana/vim-textobj-entire")
		use("kana/vim-textobj-user")
		use("machakann/vim-highlightedyank")
		use({ "mg979/vim-visual-multi", branch = "master" }) -- multi-cursor
		use("pedrohdz/vim-yaml-folds")
		use("tommcdo/vim-exchange")
		use("tpope/vim-abolish")
		use("tpope/vim-commentary")
		use({
			"tpope/vim-dispatch",
			config = function()
				vim.g["dispatch_no_maps"] = 1
			end,
		})

		use("tpope/vim-eunuch")
		use({ "tpope/vim-fugitive", requires = "tpope/vim-rhubarb" })
		use("tpope/vim-projectionist")
		use("tpope/vim-repeat")
		use("tpope/vim-rsi")
		use("tpope/vim-surround")
		use("tpope/vim-unimpaired")
		use("fladson/vim-kitty")
		use("chrisbra/colorizer")

		-- color schemes
		use({ "trevorwhitney/solarized.nvim" })
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

		use("chrisbra/NrrwRgn")

		use({
			"vim-test/vim-test",
			config = function()
				vim.g["test#strategy"] = "dispatch"
				vim.g["test#go#gotest#options"] = "-v"
				vim.g["test#javascript#jest#options"] = "--no-coverage"
				-- vim.g["test#javascript#mocha#executable"] = "npm test --"
			end,
			requires = {
				{ "tpope/vim-dispatch" },
			},
		})

		use("gabrielpoca/replacer.nvim")
		use("romainl/vim-qf")

		use({
			"lewis6991/gitsigns.nvim",
			requires = { "nvim-lua/plenary.nvim" },
		})

		use("stevearc/conform.nvim")

		installNativeLsp(use)
		installTelescope(use)
		installDap(use)
		installNvimCmp(use)
		installTreesitter(use)
	end)
end

return Packer
