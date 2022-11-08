cabb W w
cabb Wq wq
cabb Wq! wq!
cabb WQ wq
cabb WQ! wq!
cabb Q q
cabb Qa qa
cabb Qa! qa!
cabb QA qa
cabb QA! qa!
cabb Q! q!

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

inoremap <C-o> <C-x><C-o>

nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

nnoremap <C-w>q :windo close<cr>

" close the help window that pops up when using
" <C-x><C-o> autocomplete
nnoremap <silent><nowait> \p :pclose:<CR>

" search and replace
nnoremap <Leader>sr :%s/\<<C-r><C-w>\>/

" Git status
nnoremap <nowait> \s  :Git<cr>
nnoremap <nowait> \S  :Telescope git_status<cr>

" Git branches
nnoremap <nowait> \b :Branches<cr>

" Tagstack to see where you've been
nnoremap <nowait>\t :Telescope tagstack<cr>

"======== Helpful Shortcuts =========
nnoremap <nowait> \l  :<C-u>call ToggleLocationList()<CR>
nnoremap <nowait> \q  :<C-u>call ToggleQuickfixList()<CR>

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
