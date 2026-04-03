return {
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
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
			"folke/which-key.nvim",
		},
		config = function()
			require("tw.appearance").setup()
		end,
	},
	{ "nvim-tree/nvim-web-devicons", lazy = true },
	{ "chrisbra/colorizer", event = "VeryLazy" },
}
