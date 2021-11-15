function! tw#format#vim(buffer) abort
  let l:startingPos = getcurpos()
  execute 'normal! gg=G'

  call setpos('.', l:startingPos)
  execute 'normal! ^'
endfunction

function! tw#format#Format() abort
  let s:useNativeLsp = get(g:, 'use_native_lsp', 0)
  if s:useNativeLsp == 1
    " TODO: what's the LSP format?
  else
    call tw#coc#Format()
  endif
endfunction
