function! tw#trouble#MapKeys() abort
  " Vim Script
  nnoremap <leader>xx <cmd>TroubleToggle<cr>
  nnoremap <leader>xw <cmd>TroubleToggle lsp_workspace_diagnostics<cr>
  nnoremap <leader>xd <cmd>TroubleToggle lsp_document_diagnostics<cr>

  nnoremap <leader>xq <cmd>TroubleToggle quickfix<cr>
  nnoremap <leader>xl <cmd>TroubleToggle loclist<cr>

  nnoremap gR <cmd>TroubleToggle lsp_references<cr>
  nnoremap gI <cmd>TroubleToggle lsp_implementations<cr>
  nnoremap gY <cmd>TroubleToggle lsp_type_definitions<cr>

  nnoremap <nowait>\d <cmd>TroubleToggle lsp_document_diagnostics<cr>
  nnoremap <nowait>\w <cmd>TroubleToggle lsp_workspace_diagnostics<cr>
endfunction
