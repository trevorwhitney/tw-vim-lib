let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}

function! tw#fzf#selectSplit(files) abort
  let winnr = tw#select#start([],[],0)

  if type(a:files) == s:TYPE.string
    let file = a:files
    call tw#coc#openInWin(file, winnr)
  else
    for file in a:files
      call tw#coc#openInWin(file, winnr)
    endfor
  endif
endfunction


" FzfSelectSplit relies on coc-explorer
" so we only define define it for nvim
function! tw#fzf#defaultAction()
  if has('nvim')
    return {
      \ 'ctrl-t': 'tab split',
      \ 'ctrl-x': 'split',
      \ 'ctrl-v': 'vsplit',
      \ 'ctrl-s': 'FzfSelectSplit'}
  else
    return {
      \ 'ctrl-t': 'tab split',
      \ 'ctrl-x': 'split',
      \ 'ctrl-v': 'vsplit' }
  endif
endfunction

" Remap Rg function to allow more args to be passed
function! tw#fzf#ripgrep(query, fullscreen)
  let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case %s -- %s || true'

  let extra_options = ""
  let query = a:query

  " if additional options to rg are required, the query part must
  " come after --
  let query_parts = split(a:query, '--')
  if len(query_parts) > 1
    let extra_options = query_parts[0]
    let query = trim(query_parts[1])
  elseif stridx(a:query, '--') >= 0 " for when there are no options but still a --
    let query = trim(a:query[stridx(a:query, '--') + 2:strlen(a:query)-1])
  endif

  let initial_command = printf(command_fmt, extra_options, query)
  let reload_command = printf(command_fmt, extra_options, '{q}')

  let expect_keys = join(keys(g:fzf_action), ',')
  let spec = {'options': [
        \'--phony',
        \'--query', query,
        \'--expect', 'ctrl-q,'.expect_keys,
        \'--bind', g:fzf_preview_preview_key_bindings . ',change:reload:'.reload_command
        \]}
  call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
endfunction

function! tw#fzf#Configure() abort
  " ==== Fzf and fzf preview ====
  let g:fzf_preview_command = 'bat --color=always --plain --number {-1}'
  let g:fzf_preview_lines_command = 'bat --color=always --plain --number'
  let g:fzf_preview_preview_key_bindings = 'ctrl-a:select-all'
  let g:fzf_preview_grep_cmd = 'rg --line-number --no-heading --color=always'
  let g:fzf_preview_window = ['']
endfunction

function! tw#fzf#MapKeys() abort
  " ==== Fzf and fzf preview ====
  " find file (in git files if in git repo)
  nnoremap <leader>ff :GFiles<cr>
  " find file (in all files)
  nnoremap <leader>fa :Files<cr>

  " ========= grep ==============
  " use ripgrep for grep command
  if executable("rg")
    set grepprg=rg\ --vimgrep
  endif

  " Ripgrep for the word under cursor
  nnoremap <leader>rg :<C-u>Rg<Space><C-R>=expand('<cword>')<CR><CR>
  nnoremap <leader>* :<C-u>Rg<Space><C-R>=expand('<cword>')<CR><CR>
  " Ripgrep for the visually selected text
  xnoremap <leader>rg "sy:Rg -- <C-R>=substitute(substitute(@s, '\n', '', 'g'), '/', '\\/', 'g')<CR><CR>
  xnoremap <leader>* "sy:Rg -- <C-R>=substitute(substitute(@s, '\n', '', 'g'), '/', '\\/', 'g')<CR><CR>
endfunction
