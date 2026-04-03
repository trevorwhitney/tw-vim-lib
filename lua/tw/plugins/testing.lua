return {
	{
		"vim-test/vim-test",
		cmd = { "TestNearest", "TestFile", "TestSuite", "TestLast", "TestVisit" },
		dependencies = {
			"tpope/vim-dispatch",
			"nvim-lua/plenary.nvim",
		},
		config = function()
			require("tw.testing").setup()
		end,
	},
	{
		"tpope/vim-dispatch",
		lazy = true,
		init = function()
			vim.g.dispatch_no_maps = 1
		end,
	},
}
