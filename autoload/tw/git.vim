function! tw#git#browseCurrentLine()
  let command = line('.') . 'GBrowse'
  execute ':' . command
endfunction
