local very_lazy = require("tw.plugin-events").very_lazy()

return {
	{
		"kyazdani42/nvim-tree.lua",
		cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("tw.nvim-tree").setup()
		end,
	},
	{
		"christoomey/vim-tmux-navigator",
		event = very_lazy,
		cond = function()
			return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
		end,
		init = function()
			vim.g.tmux_navigator_no_mappings = 1
		end,
	},
}
