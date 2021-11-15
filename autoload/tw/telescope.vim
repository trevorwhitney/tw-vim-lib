function! tw#telescope#MapKeys() abort
  " Find files using Telescope command-line sugar.
  nnoremap <leader>ff <cmd>Telescope git_files<cr>
  nnoremap <leader>fa <cmd>Telescope find_files<cr>
  nnoremap <leader>fg <cmd>Telescope live_grep<cr>
  nnoremap <leader>fh <cmd>Telescope help_tags<cr>
  nnoremap <leader>fr <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw()<cr>

  nnoremap <nowait>\b <cmd>Telescope buffers<cr>
  nnoremap <nowait>\o <cmd>Telescope lsp_document_symbols<cr>
  nnoremap <nowait>\d <cmd>Telescope lsp_document_diagnostics>cr>
  nnoremap <nowait>\t <cmd>Telescope treesitter<cr>
endfunction
