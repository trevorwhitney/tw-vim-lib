return {
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "nvim-telescope/telescope.nvim" },
		config = function()
			local tw_config = require("tw.config")
			local opts = tw_config.get()
			if opts.lsp_support then
				require("tw.lsp").setup({
					lua_ls_root = opts.lua_ls_root,
					rocks_tree_root = opts.rocks_tree_root,
					go_build_tags = opts.go_build_tags,
				})
			end
		end,
	},
	{
		"ray-x/navigator.lua",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			{
				"ray-x/guihua.lua",
				build = "cd lua/fzy && make",
			},
			"neovim/nvim-lspconfig",
		},
	},
	{ "fatih/vim-go", ft = "go" },
}
