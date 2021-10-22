let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}

function! tw#fzf#selectSplit(files) abort
  let winnr = coc_explorer#select_wins#start([],[],0)

  if type(a:files) == s:TYPE.string
    let file = a:files
    call tw#coc#openInWin(file, winnr)
  else
    for file in a:files
      call tw#coc#openInWin(file, winnr)
    endfor
  endif
endfunction


