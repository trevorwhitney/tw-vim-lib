return {
	{
		"stevearc/conform.nvim",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			require("tw.formatting").setup()
		end,
	},
	{
		"folke/trouble.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("tw.trouble").setup()
		end,
	},
}
