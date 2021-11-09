function! tw#format#vim(buffer) abort
  let l:startingPos = getcurpos()
  execute 'normal! gg=G'

  call setpos('.', l:startingPos)
  execute 'normal! ^'
endfunction

function! tw#format#Format() abort
  if has('nvim') && CocHasProvider('format')
    call CocAction('runCommand', 'editor.action.format')
    " refresh lint warnings after reformat
    execute 'ALELint'
    return
  endif

  " default to ALEFix
  execute 'ALEFix'
endfunction
