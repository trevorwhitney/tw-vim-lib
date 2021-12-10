
function! tw#telescope#MapKeys() abort
  command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').liveGrepRaw(<q-args>)
  command! -nargs=* TelescopeLiveGrep call v:lua.require('tw.telescope').liveGrep(<q-args>)

  nnoremap <leader>tc <cmd>Telescope colorscheme<cr>

  nnoremap <leader>ff <cmd>Telescope git_files<cr>
  nnoremap <leader>fa <cmd>Telescope find_files<cr>
  nnoremap <leader>fh <cmd>Telescope help_tags<cr>
  nnoremap <leader>fo <cmd>Telescope oldfiles<cr>
  nnoremap <leader>fr <cmd>Telescope resume<cr>
  nnoremap <leader>fb <cmd>Telescope marks<cr>

  nnoremap <leader>fg <cmd>Telescope live_grep<cr>
  nnoremap <leader>fG <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw()<cr>
  xnoremap <leader>fG "sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').currentSelectionForLiveGrepRaw(@s)<cr><cr>

  nnoremap <leader>* <cmd>lua require("telescope.builtin").live_grep({ default_text = vim.fn.expand("<cword>") })<cr>
  xnoremap <leader>* "sy:TelescopeLiveGrep <C-R>=v:lua.require('tw.telescope').currentSelectionForLiveGrep(@s)<cr><cr>

  nnoremap <nowait>\b <cmd>Telescope buffers<cr>
  nnoremap <nowait>\o <cmd>Telescope lsp_document_symbols<cr>
  nnoremap <nowait>\t <cmd>Telescope treesitter<cr>
endfunction
