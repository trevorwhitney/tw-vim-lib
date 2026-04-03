return {
	{ "google/vim-jsonnet", ft = "jsonnet" },
	{ "towolf/vim-helm", ft = "helm" },
	{ "rfratto/vim-river", ft = "river" },
	{ "grafana/vim-alloy", ft = "alloy" },
	{ "fladson/vim-kitty", ft = "kitty" },
	{ "pedrohdz/vim-yaml-folds", ft = "yaml" },
	{ "mfussenegger/nvim-jdtls", ft = "java" },
	{ "junegunn/vader.vim", ft = "vader" },
	{
		"3rd/image.nvim",
		ft = { "markdown", "neorg" },
		config = function()
			require("image").setup({
				backend = "kitty",
				integrations = {
					markdown = { enabled = true },
				},
				hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
			})
		end,
	},
}
