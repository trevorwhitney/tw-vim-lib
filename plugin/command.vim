" ============= Neovim section =============
" these command rely on neovim functionality or plugins
if has('nvim')
  command! -nargs=+ -complete=file
        \ CocSelectSplit
        \ call tw#coc#selectSplit(<f-args>)

  command! -nargs=+ -complete=file
        \ FzfSelectSplit
        \ call tw#fzf#selectSplit(<f-args>)

  " ripgrepFzf includes the the open in split functionality as an
  " expected key, which relies on coc-explorer
  " so we only define this command for nvim
  command! -nargs=* -bang Rg call tw#fzf#ripgrepFzf(<q-args>, <bang>0)
endif

command! -nargs=0 GitBrowseCurrentLine
      \ call tw#git#browseCurrentLine()

command! -nargs=0 ToggleGitStatus
      \ call tw#git#toggleGitStatus()
