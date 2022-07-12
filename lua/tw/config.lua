local Config = {}

function Config.setup(sumneko_root, nix_rocks_tree)
	require("tw.config.vim-options")
	require("tw.config.appearance")
	require("tw.config.which-key")
	require("tw.config.nvim-tree")
	require("tw.config.null-ls")
	require("tw.config.telescope")
	require("tw.config.completion")
	require("tw.config.dap")
	require("tw.config.dashboard")


  local lsp_support = vim.api.nvim_eval('get(s:, "lsp_support", 0)')
  if lsp_support == 1 then
    require("tw.config.lsp").setup(sumneko_root, nix_rocks_tree)
  end
end

return Config
