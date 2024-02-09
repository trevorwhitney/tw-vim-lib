let &t_SI .= tw#tmux#WrapForTmux("\<Esc>[?2004h")
let &t_EI .= tw#tmux#WrapForTmux("\<Esc>[?2004l")

inoremap <special> <expr> <Esc>[200~ tw#xterm#XTermPasteBegin()
