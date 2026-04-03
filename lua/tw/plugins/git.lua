return {
	{
		"tpope/vim-fugitive",
		event = "VeryLazy",
		dependencies = { "tpope/vim-rhubarb" },
	},
	{ "tpope/vim-rhubarb", lazy = true },
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("tw.git").setup()
		end,
	},
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
	},
}
