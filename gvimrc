" System gvimrc file for MacVim
"
" Author:       Bjorn Winckler <bjorn.winckler@gmail.com>
" Maintainer:   macvim-dev (https://github.com/macvim-dev)


" Make sure the '<' and 'C' flags are not included in 'cpoptions', otherwise
" <CR> would not be recognized.  See ":help 'cpoptions'".
let s:cpo_save = &cpo
set cpo&vim

"
" Global default options
"

if !exists("syntax_on")
  syntax on
endif

" Load the MacVim color scheme.  This can be disabled by loading another color
" scheme with the :colorscheme command, or by adding the line
"   let macvim_skip_colorscheme=1
" to ~/.vimrc.
if !exists("macvim_skip_colorscheme") && !exists("colors_name")
    colorscheme macvim
endif

" To make tabs more readable, the label only contains the tail of the file
" name and the buffer modified flag.
if empty(&guitablabel)
  set guitablabel=%M%t
endif

" Send print jobs to Preview.app.  The user can then print from it.
set printexpr=macvim#PreviewConvertPostScript()

" askpass
let $SSH_ASKPASS = simplify($VIM . '/../../Resources') . '/macvim-askpass'
let $SUDO_ASKPASS = $SSH_ASKPASS


" This is so that HIG Cmd and Option movement mappings can be disabled by
" adding the line
"   let macvim_skip_cmd_opt_movement = 1
" to ~/.vimrc.
if !exists("macvim_skip_cmd_opt_movement")
  no   <D-Left>       <Home>
  no!  <D-Left>       <Home>
  no   <M-Left>       <C-Left>
  no!  <M-Left>       <C-Left>

  no   <D-Right>      <End>
  no!  <D-Right>      <End>
  no   <M-Right>      <C-Right>
  no!  <M-Right>      <C-Right>

  no   <D-Up>         <C-Home>
  ino  <D-Up>         <C-Home>
  no   <M-Up>         {
  ino  <M-Up>         <C-o>{

  no   <D-Down>       <C-End>
  ino  <D-Down>       <C-End>
  no   <M-Down>       }
  ino  <M-Down>       <C-o>}

  ino  <M-BS>         <C-w>
  ino  <D-BS>         <C-u>
endif " !exists("macvim_skip_cmd_opt_movement")


" This is so that the HIG shift movement related settings can be enabled by
" adding the line
"   let macvim_hig_shift_movement = 1
" to ~/.vimrc.
if exists("macvim_hig_shift_movement")
  " Shift + special movement key (<S-Left>, etc.) and mouse starts insert mode
  set selectmode=mouse,key
  set keymodel=startsel,stopsel

  " HIG related shift + special movement key mappings
  nn   <S-D-Left>     <S-Home>
  vn   <S-D-Left>     <S-Home>
  ino  <S-D-Left>     <S-Home>
  nn   <S-M-Left>     <S-C-Left>
  vn   <S-M-Left>     <S-C-Left>
  ino  <S-M-Left>     <S-C-Left>

  nn   <S-D-Right>    <S-End>
  vn   <S-D-Right>    <S-End>
  ino  <S-D-Right>    <S-End>
  nn   <S-M-Right>    <S-C-Right>
  vn   <S-M-Right>    <S-C-Right>
  ino  <S-M-Right>    <S-C-Right>

  nn   <S-D-Up>       <S-C-Home>
  vn   <S-D-Up>       <S-C-Home>
  ino  <S-D-Up>       <S-C-Home>

  nn   <S-D-Down>     <S-C-End>
  vn   <S-D-Down>     <S-C-End>
  ino  <S-D-Down>     <S-C-End>
endif " exists("macvim_hig_shift_movement")


" Restore the previous value of 'cpoptions'.
let &cpo = s:cpo_save
unlet s:cpo_save

set autoindent=true
set autoread=true
set autowrite=true
set autowriteall=true
set breakindent=true
set expandtab=true 
set incsearch=true
set wrap=false 
set number=true  
set splitright=true
set splitbelow=true
set undofile=true
set showmatch=true 
set smarttab=true 
set showmode=false 
set title=true 

set backspace={ "indent", "eol", "start" } 
set ignorecase=true 
set smartcase=true 
set mouse="a" 
set scrolloff=5
set shiftwidth=2 
set tabstop=2 
set undodir="$HOME/.macvim/undodir"
set encoding="utf-8"
set spelllang="en_us"
set guifont="JetBrainsMono Nerd Font"

" TextEdit might fail if hidden is not set.
set hidden=true

" Some servers have issues with backup files, see #649.
set backup=false
set writebackup=true

" Give more space for displaying messages.
set cmdheight=2

" Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
" delays and poor user experience.
set updatetime=300

" Don't pass messages to |ins-completion-menu|.
" set.shortmess:append("c")

" Open diffs vertically
set diffopt="vertical"
set clipboard="unnamedplus"

" folding
set foldmethod="expr"
set foldexpr="nvim_treesitter#foldexpr()"
set foldenable=false
set foldopen="insert"

" Auto completion
set completeopt={ "menu", "menuone", "longest" }
set wildignore:append({ "*\\tmp\\*", "*.swp", "*.swo", "*.zip", ".git", ".cabal-sandbox" })
set wildmode={ "longest", "list", "full" }
set wildmenu=true
set completeopt:append("longest")

" Directories
set directory={ vim.env.HOME .. "/.vim/tmp" }
set backupdir={ vim.env.HOME .. "/.vim/tmp" }

" Switchbuf
set switchbuf={ "useopen", "uselast" }

" Always show the signcolumn, otherwise it would shift the text each time
" diagnostics appear/become resolved.
set signcolumn="number"

nnoremap <silent> <C-n> :call NextHunk()<CR>
nnoremap <C-j> <C-W><C-J>
nnoremap <C-k> <C-W><C-K>
nnoremap <C-l> <C-W><C-L>
nnoremap <C-h> <C-W><C-H>
