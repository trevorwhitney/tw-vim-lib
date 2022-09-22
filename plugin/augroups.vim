" clean up unused fugitive buffers
augroup HiddenFugitive
  autocmd!
  autocmd BufReadPost fugitive://* set bufhidden=delete
  autocmd BufReadPost .git/index set nolist
augroup end

augroup Autosave
  autocmd!
  autocmd BufLeave * call tw#autosave#AutosaveBuffer()
  autocmd FocusLost * call tw#autosave#AutosaveBuffer()
augroup end

" TODO: do I need this?
"" Don't screw up folds when inserting text that might affect them, until
"" leaving insert mode. Foldmethod is local to the window. Protect against
"" screwing up folding when switching between windows.
"autocmd InsertEnter * if !exists('w:last_fdm') | let w:last_fdm=&foldmethod | setlocal foldmethod=manual | endif
"autocmd InsertLeave,WinLeave * if exists('w:last_fdm') | let &l:foldmethod=w:last_fdm | unlet w:last_fdm | endif
"

" Clear out registers on startup
augroup VimStartup
  autocmd!
  autocmd VimEnter * WipeReg
augroup end
