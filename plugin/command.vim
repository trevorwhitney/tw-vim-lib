command! -nargs=+ -complete=file
      \ CocSelectSplit
      \ call tw#coc#selectSplit(<f-args>)

command! -nargs=+ -complete=file
      \ FzfSelectSplit
      \ call tw#fzf#selectSplit(<f-args>)
