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
			require("edgy").setup(opts)
			require("tw.agent.edgy_winhl").setup()
		end,
	},
}
