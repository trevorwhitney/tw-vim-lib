return {
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-live-grep-args.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
			},
			"ThePrimeagen/refactoring.nvim",
			"nvim-telescope/telescope-dap.nvim",
			"nvim-telescope/telescope-ui-select.nvim",
			"stevearc/aerial.nvim",
		},
		config = function()
			require("tw.telescope").setup()
		end,
	},
}
