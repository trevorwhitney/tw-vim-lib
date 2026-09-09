local very_lazy = require("tw.plugin-events").very_lazy()

return {
	{
		"tpope/vim-fugitive",
		event = very_lazy,
		dependencies = { "tpope/vim-rhubarb" },
	},
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("tw.git").setup()
		end,
	},
	{
		"dlyongemallo/diffview-plus.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
	},
}
