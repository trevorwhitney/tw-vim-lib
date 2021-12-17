
function! tw#telescope#MapKeys() abort
  command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_raw(<q-args>)
  command! -nargs=* TelescopeDynamicSymbols call v:lua.require('tw.telescope').dynamic_workspace_symbols(<q-args>)

  nnoremap <leader>tc <cmd>Telescope colorscheme<cr>

  " find file
  nnoremap <leader>ff <cmd>Telescope git_files<cr>
  " find file (in all files)
  nnoremap <leader>fa <cmd>Telescope find_files<cr>
  " find help
  nnoremap <leader>fh <cmd>Telescope help_tags<cr>
  " find resume, resume last find oepration
  nnoremap <leader>fr <cmd>Telescope resume<cr>
  " find bookmark
  nnoremap <leader>fb <cmd>Telescope marks<cr>
  " find workspace symbol
  nnoremap <leader>fs <cmd>Telescope lsp_dynamic_workspace_symbols<cr>
  nnoremap <leader>* <cmd>lua require("telescope.builtin").lsp_dynamic_workspace_symbols({ default_text = vim.fn.expand("<cword>") })<cr>
  xnoremap <leader>* "sy:TelescopeDynamicSymbols <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>

  " find treesitter symbol
  nnoremap <leader>ft <cmd>Telescope treesitter<cr>

  " pnuemonic old or 'open' files
  nnoremap <leader>fo <cmd>Telescope oldfiles<cr>

  " Grep using live grep raw, which passes additional options to rg
  nnoremap <leader>fg <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw()<cr>
  " find word
  nnoremap <leader>f* <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw({ default_text = vim.fn.expand("<cword>") })<cr>
  " find selection
  xnoremap <leader>f* "sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>

  nnoremap <nowait>\b <cmd>Telescope buffers<cr>
  nnoremap <nowait>\o <cmd>Telescope lsp_document_symbols<cr>
  nnoremap <nowait>\t <cmd>Telescope treesitter<cr>
endfunction
