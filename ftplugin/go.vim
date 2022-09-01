set tabstop=2
set shiftwidth=2

let g:go_code_completion_enabled = 0
let g:go_def_mapping_enabled = 0
let g:go_build_tags = 'e2e_gem,requires_docker'
let g:go_textobj_enabled = 0
let g:go_gopls_enabled = 0

" ============== Go Commands ===========
command! -nargs=* GolangTestFocusedWithTags call tw#go#golangTestFocusedWithTags(<f-args>)

" open test in a vertical split
nmap <leader>gt  :<C-u>GoAlternate<cr>
nmap <silent>gT :<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>
nmap <leader>i   :<C-u>GoImpl<cr>

" tags
nmap <leader>tj :GoAddTags json<cr>
nmap <leader>ty :GoAddTags yaml<cr>
nmap <leader>tx :GoRemoveTags<cr>

" run tests
nmap <Leader>rp  :w<CR> :GolangTestCurrentPackage<CR>
nmap <Leader>rt  :w<CR> :GolangTestFocusedWithTags<CR>

" run integration tests
nmap <leader>ri  :w<cr> :GolangTestFocusedWithTags e2e_gme requires_docker<cr>

" delve
nmap <leader>dt <cmd>lua require('tw.languages.go').debug_go_test()<cr>
map <leader>di <cmd>lua require('tw.languages.go').debug_go_test("e2e_gme", "requires_docker")<cr>
