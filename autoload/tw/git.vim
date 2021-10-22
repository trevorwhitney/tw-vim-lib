function! tw#git#browseCurrentLine()
  let command = line('.') . 'GBrowse'
  execute ':' . command
endfunction

function! tw#git#toggleGitStatus()
  let gitIndexExpr = '.git/index'
  let bufNum = bufnr(gitIndexExpr)
  let bufVisible = bufwinnr(gitIndexExpr)

  if bufNum == -1
    execute 'Git'
  else
    if bufVisible == -1
      execute 'Git'
    else
      execute 'bdelete ' . bufNum
    endif
  endif
endfunction
