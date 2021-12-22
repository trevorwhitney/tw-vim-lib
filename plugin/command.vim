" ============= Neovim section =============
" needed for fugitive since nvim-tree.lua messes with netrw
command! -nargs=1 Browse silent exe '!xdg-open "' . tw#util#UrlEscape(<q-args>) . '"'

command! -nargs=0 GitBrowseCurrentLine call tw#git#browseCurrentLine()

command! -nargs=0 ToggleGitStatus call tw#git#toggleGitStatus()

command! -nargs=* GolangTestFocusedWithTags call tw#go#golangTestFocusedWithTags(<f-args>)

command! WipeReg for i in range(34,122) | silent! call setreg(nr2char(i), []) | endfor
