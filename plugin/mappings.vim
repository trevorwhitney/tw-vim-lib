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

" ====== Readline / RSI =======
inoremap <c-k> <c-o>D
cnoremap <c-k> <c-\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<CR>
