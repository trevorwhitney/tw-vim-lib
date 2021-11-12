local Packer = {}

function Packer.install(use)
  require('packer').startup(function()
    use 'wbthomason/packer.nvim' -- Package manager
    use 'trevorwhitney/tw-vim-lib' -- all my vim customizations

    use 'AndrewRadev/bufferize.vim'
    use 'LeafCage/yankround.vim'
    use 'benmills/vimux'
    use 'benmills/vimux-golang'
    use 'christoomey/vim-tmux-navigator'
    use 'coachshea/vim-textobj-markdown'
    use 'dense-analysis/ale'
    use 'easymotion/vim-easymotion'
    use 'folke/which-key.nvim'
    use 'google/vim-jsonnet'
    use 'junegunn/vader.vim'
    use 'jvirtanen/vim-hcl'
    use 'kana/vim-textobj-entire'
    use 'kana/vim-textobj-user'
    use 'kyazdani42/nvim-web-devicons'
    use 'machakann/vim-highlightedyank'
    use {'mg979/vim-visual-multi', branch = 'master' }
    use 'nvim-treesitter/nvim-treesitter' -- Highlight, edit, and navigate code using a fast incremental parsing library
    use 'nvim-treesitter/nvim-treesitter-textobjects' -- Additional textobjects for treesitter
    use 'pedrohdz/vim-yaml-folds'
    use 'roxma/vim-tmux-clipboard'
    use 'tommcdo/vim-exchange'
    use 'tpope/vim-abolish'
    use 'tpope/vim-commentary'
    use 'tpope/vim-dispatch'
    use 'tpope/vim-eunuch'
    use 'tpope/vim-fugitive'
    use 'tpope/vim-projectionist'
    use 'tpope/vim-repeat'
    use 'tpope/vim-rhubarb'
    use 'tpope/vim-rsi'
    use 'tpope/vim-surround'
    use 'tpope/vim-unimpaired'

    -- replace airline with lightline?
    use 'vim-airline/vim-airline'
    use 'vim-airline/vim-airline-themes'
    -- use 'itchyny/lightline.vim' -- Fancier statusline

    -- begin coc
    use {'neoclide/coc-highlight', run = 'yarn install --frozen-lockfile'}
    use {'neoclide/coc-pairs', branch = 'master', run = 'yarn install --frozen-lockfile' }
    use { 'weirongxu/coc-explorer', branch = 'master', run = 'yarn install --frozen-lockfile'}
     --- end coc

     -- will be repaced by telescope
    use {'junegunn/fzf', run = function() vim.fn['fzf#install']() end }
    use {'junegunn/fzf.vim', run = function() vim.fn['fzf#install']() end }
    use {'yuki-yano/fzf-preview.vim', branch = 'release/rpc' }
    -- UI to select things (files, grep results, open buffers...)
    -- use { 'nvim-telescope/telescope.nvim', requires = { 'nvim-lua/plenary.nvim' } }

    -- coc-git will be replaced by gitsigns
    use {'neoclide/coc-git', run = 'yarn install --frozen-lockfile'}
    -- Add git related info in the signs columns and popups
    -- use { 'lewis6991/gitsigns.nvim', requires = { 'nvim-lua/plenary.nvim' } }

    -- native lsp will replace coc
    use {'neoclide/coc.nvim',branch = 'master', run = 'yarn install --frozen-lockfile' }
    use {'neoclide/coc-yaml', run = 'yarn install --frozen-lockfile'}
    use {'neoclide/coc-json', run = 'yarn install --frozen-lockfile'}
    use {'neoclide/coc-tsserver', run = 'yarn install --frozen-lockfile'}
    use {'iamcco/coc-spell-checker', run = 'yarn install --frozen-lockfile'}
    use {'iamcco/coc-vimlsp', run = 'yarn install --frozen-lockfile'}
    use {'josa42/coc-lua', run = 'yarn install --frozen-lockfile'}
    use {'josa42/coc-go', run = 'yarn install --frozen-lockfile'}
    use {'josa42/coc-sh', run = 'yarn install --frozen-lockfile'}
    use { 'fannheyward/coc-markdownlint', run = 'yarn install --frozen-lockfile' }
    use { 'fannheyward/coc-sql', run = 'yarn install --frozen-lockfile' }
    use 'antoinemadec/coc-fzf'
    -- use 'neovim/nvim-lspconfig' -- Collection of configurations for built-in LSP client
    -- use 'hrsh7th/nvim-cmp' -- Autocompletion plugin
    -- use 'hrsh7th/cmp-nvim-lsp'
    -- end native lsp

    -- coc-snippets will be replaced by lua snip
    use {'neoclide/coc-snippets', run = 'yarn install --frozen-lockfile'}
    -- use 'L3MON4D3/LuaSnip' -- Snippets plugin
    -- use 'saadparwaiz1/cmp_luasnip'

    use 'sebdah/vim-delve'
    use 'shaunsingh/solarized.nvim'
  end)
end

return Packer
