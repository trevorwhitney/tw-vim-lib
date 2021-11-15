if g:use_native_lsp == 1
  "TODO: are there any specific go stuff?
  "impl at cursor and toggle test are important
else
  " open test in a vertical split
  nmap <leader>gt  :<C-u>CocCommand go.test.toggle<cr>
  nmap <silent>gT :<C-u>wincmd o<cr> :vsplit<cr> :<C-u>CocCommand go.test.toggle<cr>
  nmap <leader>t   :<C-u>CocCommand go.test.generate.function<cr>
  nmap <leader>i   :<C-u>CocCommand go.impl.cursor<cr>

  " tags
  nmap <leader>tj :CocCommand go.tags.add json<cr>
  nmap <leader>ty :CocCommand go.tags.add yaml<cr>
  nmap <leader>tx :CocCommand go.tags.clear<cr>
endif

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
