" ============= Git =============
" needed for fugitive since nvim-tree.lua messes with netrw
command! -nargs=1 Browse silent exe '!xdg-open "' . tw#util#UrlEscape(<q-args>) . '"'
command! -nargs=0 Branches Telescope git_branches 
command! -nargs=0 Gpr Git pull --rebase
command! -nargs=0 Gci Git commit

" ============== Misc ===========
command! WipeReg for i in range(34,122) | silent! call setreg(nr2char(i), []) | endfor

