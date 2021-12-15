
function! tw#telescope#MapKeys() abort
  command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').liveGrepRaw(<q-args>)

  nnoremap <leader>tc <cmd>Telescope colorscheme<cr>

  nnoremap <leader>ff <cmd>Telescope git_files<cr>
  nnoremap <leader>fa <cmd>Telescope find_files<cr>
  nnoremap <leader>fh <cmd>Telescope help_tags<cr>
  nnoremap <leader>fr <cmd>Telescope resume<cr>
  nnoremap <leader>fb <cmd>Telescope marks<cr>

  " pnuemonic old or 'open' files
  nnoremap <leader>fo <cmd>Telescope oldfiles<cr>

  " Grep using live grep raw, which passes additional options to rg
  nnoremap <leader>fg <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw()<cr>
  nnoremap <leader>* <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw({ default_text = vim.fn.expand("<cword>") })<cr>
  xnoremap <leader>* "sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').currentSelection(@s)<cr><cr>

  nnoremap <nowait>\b <cmd>Telescope buffers<cr>
  nnoremap <nowait>\o <cmd>Telescope lsp_document_symbols<cr>
  nnoremap <nowait>\t <cmd>Telescope treesitter<cr>
endfunction
