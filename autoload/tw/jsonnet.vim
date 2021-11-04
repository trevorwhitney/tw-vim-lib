function! tw#jsonnet#expand()
  " check if the file is a tanka file, and if so get its JSONNET_PATH
  let jsonnet_path = system('tk tool jpath ' . shellescape(expand('%')))
  if v:shell_error
    let output = system('jsonnet-tool expand ' . shellescape(expand('%')))
  else
    let output = system("JSONNET_PATH=\"" . jsonnet_path . "\" jsonnet-tool expand " . shellescape(expand('%')))
  endif
  vnew
  setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile ft=jsonnet
  put! = output
endfunction


function! tw#jsonnet#eval()
  " check if the file is a tanka file or not
  let output = system("tk tool jpath " . shellescape(expand('%')))
  if v:shell_error
    let output = system("jsonnet " . shellescape(expand('%')))
  else
    let output = system("tk eval " . shellescape(expand('%')))
  endif
  vnew
  setlocal nobuflisted buftype=nofile bufhidden=wipe noswapfile ft=json
  put! = output
endfunction

" set JSONNET_PATH and restart language server
function! tw#jsonnet#resetJsonnetLSP()
    " requires CoC to be ready, so we bail if it's not
    if g:coc_service_initialized != 1
      return
    endif

    let output=system('tk tool jpath ' . shellescape(expand('%')))
    if !v:shell_error
      let $JSONNET_PATH=output
      let l:services = CocAction('services')
      for service in l:services
        if service['id'] ==? 'languageserver.jsonnet'
          call CocAction('toggleService', 'languageserver.jsonnet')
          break
        endif
      endfor

      call coc#config('languageserver.jsonnet', {
          \ 'command': "jsonnet-language-server",
          \ 'env': {
          \   'JSONNET_PATH': output,
          \ },
          \ 'filetypes': [
          \   'jsonnet'
          \ ],
          \ 'trace.server': 'verbose',
          \ 'settings': {},
        \})

      sleep 100m
      set filetype=jsonnet
    endif
endfunction
