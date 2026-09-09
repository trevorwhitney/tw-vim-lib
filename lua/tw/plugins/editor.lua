local very_lazy = require("tw.plugin-events").very_lazy()

return {
	{
		"folke/which-key.nvim",
		event = very_lazy,
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
	{ "andymass/vim-matchup", event = very_lazy },
	{ "mg979/vim-visual-multi", branch = "master", event = very_lazy },
	{
		"ThePrimeagen/refactoring.nvim",
		event = very_lazy,
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
			"lewis6991/async.nvim",
		},
		config = function()
			require("refactoring").setup({})
		end,
	},
	{ "tpope/vim-surround", event = very_lazy },
	{ "tpope/vim-repeat", event = very_lazy },
	{ "tpope/vim-rsi", event = very_lazy },
	{ "tpope/vim-abolish", event = very_lazy },
	{ "tpope/vim-eunuch", event = very_lazy },
	{ "kana/vim-textobj-user", event = very_lazy },
	{
		"kana/vim-textobj-entire",
		event = very_lazy,
		dependencies = { "kana/vim-textobj-user" },
	},
	{
		"coachshea/vim-textobj-markdown",
		event = very_lazy,
		dependencies = { "kana/vim-textobj-user" },
	},
	{ "chrisbra/NrrwRgn", event = very_lazy },
	{ "gabrielpoca/replacer.nvim", event = very_lazy },
	{ "romainl/vim-qf", event = very_lazy },
	{ "ii14/neorepl.nvim", cmd = "Repl" },
	{
		"stevearc/aerial.nvim",
		event = very_lazy,
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
