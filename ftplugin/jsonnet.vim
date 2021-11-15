" disable yaml auto-indenting logic
setlocal indentexpr=

" TODO: rewrite for nvim lsp
" call tw#jsonnet#updateJsonnetPath()
nmap <leader>b :call tw#jsonnet#eval()<cr>
nmap <leader>e :call tw#jsonnet#expand()<cr>
