return {
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		keys = {
			{
				"<leader>gg",
				"<cmd>lua require('tw.telescope-git-branch-diff').git_branch_diff_picker()<cr>",
				desc = "Diff Against Branch (Branch Picker)",
			},
			{
				"<leader>gg",
				"<C-\\><C-n><cmd>lua require('tw.telescope-git-branch-diff').git_branch_diff_picker()<cr>",
				mode = "t",
				desc = "Diff Against Branch (Branch Picker)",
			},
		},
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
