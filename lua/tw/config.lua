local Config = {}

function Config.setup()
  require('tw.config.vim-options')
  require('tw.config.appearance')
  require('tw.config.treesitter')
  require('tw.config.which-key')
  require('tw.config.nvim-tree')

  require('nvim-autopairs').setup {}
end

return Config
