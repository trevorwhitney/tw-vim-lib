local Config = {}

function Config.setup(lua_ls_root, nix_rocks_tree)
  -- Use CapitalCamelCase to avoid collisioins with global lua modules
  require("tw.config.VimOptions").setup()
  require("tw.config.Appearance").setup()
  require("tw.config.WhichKey").setup()
  require("tw.config.NvimTree").setup()
  require("tw.config.NullLs").setup()
  require("tw.config.Telescope").setup()
  require("tw.config.Dap").setup()
  require("tw.config.Treesitter").setup()
  require("tw.config.Copilot").setup()
  require("tw.config.NvimCmp").setup()
  require("tw.config.Git").setup()

  local lsp_support = vim.api.nvim_eval('get(s:, "lsp_support", 0)')
  if lsp_support == 1 then
    require("tw.config.Lsp").setup(lua_ls_root, nix_rocks_tree)
  end
end

return Config
