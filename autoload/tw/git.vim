function! tw#git#browseCurrentLine()
  let command = line('.') . 'GBrowse'
  execute ':' . command
endfunction

function! tw#git#toggleGitStatus()
  let bufName = bufname('fugitive:///*/.git')
  let bufNum = bufnr(bufName)
  let bufVisible = bufwinnr(bufNum)

  if bufNum == -1
    execute 'Git'
  else
    if bufVisible == -1 || bufVisible == 1
      execute 'Git'
    else
      execute 'bdelete ' . bufNum
    endif
  endif
endfunction
