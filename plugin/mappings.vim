cabb W w
cabb Wq wq
cabb WQ wq
cabb Q q
cabb Qa qa

" <C-q> is for tmux
noremap <C-q> <Nop>

map <Leader>z :'<,'>sort<CR>

"==== Some custom text objects ====
" line text object
xnoremap il g_o^
onoremap il :normal vil<CR>
xnoremap al $o^
onoremap al :normal val<CR>

"========== Keybindings ==========
imap jj <Esc>
cmap w!! w !sudo tee > /dev/null %

nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

nnoremap <C-w>q :windo close<cr>

" paste the 0 register
nnoremap <silent><nowait> \p "0p
nnoremap <silent><nowait> \P "0P

" search and replace
nnoremap <Leader>sr :%s/\<<C-r><C-w>\>/

" ====== Git (vim-fugitive) =====

" Git status, show currently changed files
nmap <leader>gb   :Gitsigns blame_line<CR>
nmap <leader>gB   :Git blame<CR>

" pneumonic git diff
nmap <leader>gd   :Gdiffsplit<CR>
nmap <leader>gD   :Gdiffsplit @~1<CR>

nnoremap <leader>go   :GitBrowseCurrentLine<cr>
xnoremap <leader>go   :'<,'>GBrowse<CR>

" pneumonic git commit
nmap <leader>gk       :Git commit<CR>

" Git status
nnoremap <nowait> \s  :ToggleGitStatus<cr>
nnoremap <nowait> \S  :Telescope git_status<cr>

" Git branches
nnoremap <nowait> \b :Branches<cr>

" Tagstack to see where you've been
nnoremap <nowait>\t :Telescope tagstack<cr>

" pneumonic git history
nmap <leader>gh   :0Gclog!<CR>
" pneumonic git log
nmap <leader>gl   :<C-u>Git log -n 50 --graph --decorate --oneline<cr>

"======== Helpful Shortcuts =========
nnoremap <nowait> \l  :<C-u>call ToggleLocationList()<CR>
nnoremap <nowait> \c  :<C-u>call ToggleQuickfixList()<CR>

" ====== easy-motion ======
map <leader>w <Plug>(easymotion-bd-w)
nmap <Leader>w <Plug>(easymotion-overwin-w)

" ====== Readline / RSI =======
inoremap <c-k> <c-o>D
cnoremap <c-k> <c-\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<CR>

"=== NvimTree
nnoremap <silent><nowait> <leader>\ :<c-u>NvimTreeToggle<cr>
nnoremap <silent><nowait> \| :<c-u>NvimTreeFindFile<cr>

"=== Dashboard
nnoremap <leader>sl :SessionLoad<cr>
nnoremap <leader>ss :SessionSave<cr>
nnoremap <leader>cn :DashboardNewFile<cr>
