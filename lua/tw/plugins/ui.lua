return {
	{
		"rebelot/kanagawa.nvim",
		name = "kanagawa",
		priority = 1000,
		lazy = false,
	},
  {
    'projekt0n/github-nvim-theme',
    name = 'github-theme',
    lazy = false,    -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
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
