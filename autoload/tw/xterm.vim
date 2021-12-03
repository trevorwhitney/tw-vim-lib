function! tw#xterm#XTermPasteBegin() abort
  set pastetoggle=<Esc>[201~
  set paste
  return ''
endfunction
