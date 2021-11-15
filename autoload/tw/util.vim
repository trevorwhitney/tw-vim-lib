function! tw#util#shellCommandSeperator()
  if empty(matchstr($SHELL, 'fish'))
    return '&&'
  else
    return '; and'
  endif
endfunction

" Escape special characters in url
function! tw#util#UrlEscape(string)
  return substitute(a:string, '#', '\\#', 'g')
endfunction
