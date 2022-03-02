local Config = {}

function Config.setup(sumneko_root, nix_rocks_tree, jdtls_home)
	require("tw.config.vim-options")
	require("tw.config.appearance")
	require("tw.config.which-key")
	require("tw.config.nvim-tree")
	require("tw.config.null-ls")
	require("tw.config.telescope")
	require("tw.config.completion")
	require("tw.config.dap")

	require("tw.config.lsp").setup(sumneko_root, nix_rocks_tree, jdtls_home)
end

return Config
