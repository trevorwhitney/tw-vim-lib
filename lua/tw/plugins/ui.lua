local very_lazy = require("tw.plugin-events").very_lazy()

return {
	{
		"rebelot/kanagawa.nvim",
		name = "kanagawa",
		priority = 1000,
		lazy = false,
	},
	{
		"projekt0n/github-nvim-theme",
		name = "github-theme",
		lazy = false,
		priority = 1000,
		opts = {
			options = {
				modules = {
					diffchar = false,
				},
			},
			groups = {
				all = {
					DiffAdd = { bg = "palette.success.subtle" },
					DiffDelete = { bg = "palette.danger.subtle" },
					DiffChange = { bg = "palette.attention.subtle" },
					DiffText = { bg = "palette.attention.muted" },
					TwDiffviewAddText = { bg = "palette.success.muted" },
					TwDiffviewDeleteText = { bg = "palette.danger.muted" },
				},
			},
		},
	},
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
		lazy = false,
		opts = {
			background = {
				light = "latte",
				dark = "mocha",
			},
		},
	},
	{
		"nvim-lualine/lualine.nvim",
		event = very_lazy,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
			"folke/which-key.nvim",
		},
		config = function()
			require("tw.appearance").setup()
		end,
	},
	{ "nvim-tree/nvim-web-devicons", lazy = true },
	{ "chrisbra/colorizer", event = very_lazy },
}
