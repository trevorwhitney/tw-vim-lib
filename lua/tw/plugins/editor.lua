return {
	{
		"folke/which-key.nvim",
		dependencies = { "echasnovski/mini.nvim" },
		config = function()
			require("tw.which-key").setup()
		end,
	},
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		config = function()
			require("nvim-autopairs").setup({})
		end,
	},
	{ "andymass/vim-matchup", event = "VeryLazy" },
	{ "mg979/vim-visual-multi", branch = "master", event = "VeryLazy" },
	{
		"ThePrimeagen/refactoring.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
		config = function()
			require("refactoring").setup({})
		end,
	},
	{ "tpope/vim-surround", event = "VeryLazy" },
	{ "tpope/vim-repeat", event = "VeryLazy" },
	{ "tpope/vim-rsi", event = "VeryLazy" },
	{ "tpope/vim-abolish", event = "VeryLazy" },
	{ "tpope/vim-eunuch", event = "VeryLazy" },
	{ "kana/vim-textobj-user", event = "VeryLazy" },
	{
		"kana/vim-textobj-entire",
		event = "VeryLazy",
		dependencies = { "kana/vim-textobj-user" },
	},
	{
		"coachshea/vim-textobj-markdown",
		event = "VeryLazy",
		dependencies = { "kana/vim-textobj-user" },
	},
	{ "chrisbra/NrrwRgn", event = "VeryLazy" },
	{ "gabrielpoca/replacer.nvim", event = "VeryLazy" },
	{ "romainl/vim-qf", event = "VeryLazy" },
	{ "ii14/neorepl.nvim", cmd = "Repl" },
	{
		"stevearc/aerial.nvim",
		event = "VeryLazy",
		dependencies = { "folke/which-key.nvim" },
		config = function()
			local wk = require("which-key")
			require("aerial").setup({
				layout = {
					max_with = { 50, 0.2 },
				},
				on_attach = function(_)
					local keymap = {
						{
							"{",
							"<cmd>AerialPrev<CR>",
							desc = "Jump to previous symbol",
							nowait = false,
							remap = false,
						},
						{
							"}",
							"<cmd>AerialNext<CR>",
							desc = "Jump to next symbol",
							nowait = false,
							remap = false,
						},
					}
					wk.add(keymap)
				end,
			})
		end,
	},
	{
		"nvim-pack/nvim-spectre",
		cmd = "Spectre",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = { live_update = true, use_trouble_qf = true },
	},
}
