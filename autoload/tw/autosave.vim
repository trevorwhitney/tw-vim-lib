" ======== Auto Save =========
function! tw#autosave#AutosaveBuffer() abort
  " Don't try to autosave fugitive buffers
  " or buffers without filenames
  if @% =~? '^fugitive:' || @% =~? '^octo:' || @% ==# ''
    return
  endif

  update
endfun
