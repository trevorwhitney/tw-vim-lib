function! tw#coc#openInWin(filename, winnr) abort
  try
    execute a:winnr.'wincmd w'
    execute 'edit '. a:filename
  catch
    execute 'edit '. a:filename
  endtry
endfunction

function! tw#coc#selectSplit(...) abort
  " if the first argument starts with +, store that in
  " where to be executed after opening
  if a:1 =~? '^+'
    let where = a:1[1:]
    let files = a:000[1:]
  else
    let files = a:000
  endif

  " use coc_explorer window selector to pick the window
  " to open in
  let winnr = tw#select#start([],[],0)
  for file in files
    if tw#coc#openInWin(file, winnr) > 0 && exists('where')
      exe where
    endif
  endfor
endfunction
