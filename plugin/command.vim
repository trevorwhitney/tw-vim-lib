" ============= Neovim section =============
" these command rely on neovim functionality or plugins
if has('nvim')
  command! -nargs=+ -complete=file
        \ CocSelectSplit
        \ call tw#coc#selectSplit(<f-args>)

  command! -nargs=+ -complete=file
        \ FzfSelectSplit
        \ call tw#fzf#selectSplit(<f-args>)
endif

command! -nargs=0 GitBrowseCurrentLine
      \ call tw#git#browseCurrentLine()

command! -nargs=0 ToggleGitStatus
      \ call tw#git#toggleGitStatus()

command! -nargs=* -bang Rg call tw#fzf#ripgrep(<q-args>, <bang>0)

command! -nargs=* GolangTestFocusedWithTags call tw#go#golangTestFocusedWithTags(<f-args>)
command! -nargs=* DlvTestFocused call tw#go#dlvTestFocused(<f-args>)
