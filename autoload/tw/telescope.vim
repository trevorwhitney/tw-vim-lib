function! tw#telescope#CurrentSelectionForLiveGrep(text) abort
  return v:lua.require('tw.telescope').currentSelectionForLiveGrep(a:text)
endfunction

function! tw#telescope#CurrentSelectionForLiveGrepRaw(text) abort
  return v:lua.require('tw.telescope').currentSelectionForLiveGrepRaw(a:text)
endfunction

function! tw#telescope#LiveGrepRawSelection(text) abort
  lua << EOF
  local text = vim.api.nvim_eval("a:text")
  require("telescope").extensions.live_grep_raw.live_grep_raw({ default_text = '"' .. text .. '"'})
EOF
endfunction

function! tw#telescope#LiveGrepSelection(text) abort
  lua << EOF
  local text = vim.api.nvim_eval("a:text")
  require("telescope.builtin").live_grep({ default_text = text })
EOF
endfunction

command! -nargs=* TelescopeLiveGrepRaw call tw#telescope#LiveGrepRawSelection(<q-args>)
command! -nargs=* TelescopeLiveGrep call tw#telescope#LiveGrepSelection(<q-args>)

function! tw#telescope#MapKeys() abort
  " Find files using Telescope command-line sugar.
  nnoremap <leader>ff <cmd>Telescope git_files<cr>
  nnoremap <leader>fa <cmd>Telescope find_files<cr>
  nnoremap <leader>fg <cmd>Telescope live_grep<cr>
  nnoremap <leader>fh <cmd>Telescope help_tags<cr>

  nnoremap <leader>fr <cmd>lua require("telescope").extensions.live_grep_raw.live_grep_raw()<cr>
  xnoremap <leader>fr "sy:TelescopeLiveGrepRaw <C-R>=tw#telescope#CurrentSelectionForLiveGrepRaw(@s)<cr><cr>

  nnoremap <leader>* <cmd>lua require("telescope.builtin").live_grep({ default_text = vim.fn.expand("<cword>") })<cr>
  xnoremap <leader>* "sy:TelescopeLiveGrep <C-R>=tw#telescope#CurrentSelectionForLiveGrep(@s)<cr><cr>

  nnoremap <nowait>\b <cmd>Telescope buffers<cr>
  nnoremap <nowait>\o <cmd>Telescope lsp_document_symbols<cr>
  nnoremap <nowait>\t <cmd>Telescope treesitter<cr>
endfunction
