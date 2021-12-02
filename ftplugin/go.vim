" setlocal foldmethod=expr
" setlocal foldexpr=nvim_treesitter#foldexpr()
"
let g:go_code_completion_enabled = 0
let g:go_def_mapping_enabled = 0
let g:go_build_tags = 'e2e_gem,requires_docker'
let g:go_textobj_enabled = 0
let g:go_gopls_enabled = 0

" open test in a vertical split
nmap <leader>gt  :<C-u>GoAlternate<cr>
nmap <silent>gT :<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>
nmap <leader>i   :<C-u>GoImpl<cr>

" tags
nmap <leader>tj :GoAddTags json<cr>
nmap <leader>ty :GoAddTags yaml<cr>
nmap <leader>tx :GoRemoveTags<cr>

" run tests
nmap <Leader>rp  :wa<CR> :GolangTestCurrentPackage<CR>
nmap <Leader>rt  :wa<CR> :GolangTestFocusedWithTags<CR>

" run integration tests
nmap <leader>ri  :wa<cr> :GolangTestFocusedWithTags e2e_gme requires_docker<cr>

" delve
nmap <leader>bp  :DlvToggleBreakpoint<cr>
nmap <leader>dt  :wa<cr> :DlvTestFocused<cr>

" delve integration test
nmap <leader>di  :wa<cr> :DlvTestFocused e2e_gme requires_docker<cr>

" search
nmap <leader>gr :Rg -g '**/*.go' --