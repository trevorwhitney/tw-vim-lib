return {
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		dependencies = { "copilotlsp-nvim/copilot-lsp" },
		init = function()
			vim.g.copilot_nes_debounce = 500
		end,
		config = function()
			require("tw.ai").setup()
		end,
	},
	{
		"zbirenbaum/copilot-cmp",
		dependencies = { "zbirenbaum/copilot.lua" },
		config = function()
			require("copilot_cmp").setup()
		end,
	},
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = "markdown",
		opts = { latex = { enabled = false } },
	},
	{ "HakonHarnes/img-clip.nvim", event = "VeryLazy" },
}
