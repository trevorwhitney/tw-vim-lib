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
