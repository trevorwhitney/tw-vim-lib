local Config = {}

function Config.setup(lua_ls_root, nix_rocks_tree)
  require("tw.config.vim-options").setup()
  require("tw.config.appearance").setup()
  require("tw.config.which-key").setup()
  require("tw.config.nvim-tree").setup()
  require("tw.config.null-ls").setup()
  require("tw.config.telescope").setup()
  require("tw.config.dap").setup()
  require("tw.config.treesitter").setup()
  require("tw.config.copilot").setup()
  require("tw.config.nvim-cmp").setup()
  require("tw.config.gitsigns").setup()

  local lsp_support = vim.api.nvim_eval('get(s:, "lsp_support", 0)')
  if lsp_support == 1 then
    require("tw.config.lsp").setup(lua_ls_root, nix_rocks_tree)
  end
end

return Config
