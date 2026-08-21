return {
	{
		"folke/edgy.nvim",
		event = "VeryLazy",
		init = function()
			vim.opt.laststatus = 3
			vim.opt.splitkeep = "screen"
		end,
		opts = require("tw.agent.edgy_config"),
		config = function(_, opts)
			-- Before setup: this reads a dragged edgebar's size, and autocmds run
			-- in registration order, so it has to beat edgy's own WinResized
			-- handler to the window.
			require("tw.agent.edgy_resize").setup()
			require("edgy").setup(opts)
			require("tw.agent.edgy_winhl").setup()
		end,
	},
}
