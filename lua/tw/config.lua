local Config = {}

function Config.setup(lua_ls_root, nix_rocks_tree)
  -- Use CapitalCamelCase to avoid collisioins with global lua modules
  require("tw.config.vim-options").setup()
  require("tw.config.appearance").setup()
  require("tw.config.WhichKey").setup()
  require("tw.config.nvim-tree").setup()
  require("tw.config.null-ls").setup()
  require("tw.config.Telescope").setup()
  require("tw.config.Dap").setup()
  require("tw.config.treesitter").setup()
  require("tw.config.copilot").setup()
  require("tw.config.nvim-cmp").setup()
  require("tw.config.git").setup()

  local lsp_support = vim.api.nvim_eval('get(s:, "lsp_support", 0)')
  if lsp_support == 1 then
    require("tw.config.lsp").setup(lua_ls_root, nix_rocks_tree)
  end
end

return Config
