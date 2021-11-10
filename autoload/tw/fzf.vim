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

