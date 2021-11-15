function! tw#coc#openInWin(filename, winnr) abort
  try
    execute a:winnr.'wincmd w'
    execute 'edit '. a:filename
  catch
    execute 'edit '. a:filename
  endtry
endfunction

function! tw#coc#selectSplit(...) abort
  " if the first argument starts with +, store that in
  " where to be executed after opening
  if a:1 =~? '^+'
    let where = a:1[1:]
    let files = a:000[1:]
  else
    let files = a:000
  endif

  " use coc_explorer window selector to pick the window
  " to open in
  let winnr = tw#select#start([],[],0)
  for file in files
    if tw#coc#openInWin(file, winnr) > 0 && exists('where')
      exe where
    endif
  endfor
endfunction

function! tw#coc#Format() abort
  if has('nvim') && CocHasProvider('format')
    call CocAction('runCommand', 'editor.action.format')
    " refresh lint warnings after reformat
    execute 'ALELint'
    return
  endif

  " default to ALEFix
  execute 'ALEFix'
endfunction

function! tw#coc#Configure() abort
  augroup mygroup
    autocmd!
    " Setup formatexpr specified filetype(s).
    autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
    " Update signature help on jump placeholder.
    autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
  augroup end

endfunction


function! tw#coc#CheckBackSpace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

function! tw#coc#MapKeys() abort
  " formatter
  nnoremap <leader>= :call tw#format#Format()<cr>
  xmap <silent> <leader>=  <Plug>(coc-format-selected)


  " Use tab for trigger completion with characters ahead and navigate.
  " NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
  " other plugin before putting this into your config.
  inoremap <silent><expr> <TAB>
        \ pumvisible() ? "\<C-n>" :
        \ tw#coc#CheckBackSpace() ? "\<TAB>" :
        \ coc#refresh()
  inoremap <expr> <S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"


  " Use enter to seelect auto-complete suggestion
  inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

  inoremap <silent><expr> <c-space> coc#refresh()

  " close coc floats when they get annoying
  inoremap kk <C-o>:call coc#float#close_all()<cr>

  " GoTo code navigation.
  nmap <silent> gd <Plug>(coc-definition)
  nmap <silent> gD :<C-u>call CocAction('jumpDefinition', 'CocSelectSplit')<CR>
  nmap <silent> gy <Plug>(coc-type-definition)
  nmap <silent> gY :<C-u>call CocAction('jumpTypeDefinition', 'CocSelectSplit')<CR>
  nmap <silent> gi :<C-u>CocCommand fzf-preview.CocImplementations<CR>
  nmap <silent> gr :<C-u>CocCommand fzf-preview.CocReferences<CR>

  " Use <leader>h to show documentation in preview window.
  nnoremap <leader>h :call tw#coc#ShowDocumentation()<cr>

  " Applying codeAction to the selected region.
  " Example: `<leader>aap` for current paragraph
  xmap <leader>a  <Plug>(coc-codeaction-selected)
  nmap <leader>a  <Plug>(coc-codeaction-selected)
  nmap <leader>aa  <Plug>(coc-codeaction-cursor)
  nmap <leader>ac  <Plug>(coc-codeaction)

  " Apply AutoFix to problem on the current line.
  nmap <leader><cr>  <Plug>(coc-fix-current)

  xmap <leader>rf   <Plug>(coc-refactor)

  " Map function and class text objects
  " NOTE: Requires 'textDocument.documentSymbol' support from the language server.
  xmap if <Plug>(coc-funcobj-i)
  omap if <Plug>(coc-funcobj-i)
  xmap af <Plug>(coc-funcobj-a)
  omap af <Plug>(coc-funcobj-a)
  xmap ic <Plug>(coc-classobj-i)
  omap ic <Plug>(coc-classobj-i)
  xmap ac <Plug>(coc-classobj-a)
  omap ac <Plug>(coc-classobj-a)

  " Remap <C-f> and <C-b> for scroll float windows/popups.
  if has('nvim-0.4.0') || has('patch-8.2.0750')
    nnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    nnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
    inoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
    inoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
    vnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    vnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
  endif

  " Use CTRL-S for selections ranges.
  " Requires 'textDocument/selectionRange' support of language server.
  nmap <silent> <C-s> <Plug>(coc-range-select)
  xmap <silent> <C-s> <Plug>(coc-range-select)

  " Add `:Fold` command to fold current buffer.
  command! -nargs=? Fold :call     CocAction('fold', <f-args>)

  " Add `:OR` command for organize imports of the current buffer.
  command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')

  " Mappings for CoCList
  " Show all diagnostics.
  nnoremap <nowait> \a  :<C-u>CocCommand fzf-preview.CocDiagnostics<cr>
  " Show diagnostics for current file
  nnoremap <nowait> \x  :<C-u>CocCommand fzf-preview.CocCurrentDiagnostics<cr>
  " Show recent files
  nnoremap <nowait> \e  :<C-u>CocCommand fzf-preview.MruFiles<cr>
  " Show open buffers
  nnoremap <nowait> \b  :<C-u>CocCommand fzf-preview.Buffers<cr>
  " Show commands.
  nnoremap <nowait> \c  :<C-u>CocList commands<cr>
  " Find symbol of current document.
  nnoremap <nowait> \o  :<C-u>CocList outline<cr>
  " Resume latest coc list.
  nnoremap <nowait> \r  :<C-u>CocListResume<CR>
  " Resume latest grep
  nnoremap <nowait> \g  :<C-u>CocCommand fzf-preview.ProjectGrepRecall<CR>

  " Do default action for next (search/liSt) item.
  nnoremap <silent><nowait> ]s  :<C-u>CocNext<CR>
  " Do default action for previous (search/liSt) item.
  nnoremap <silent><nowait> [s  :<C-u>CocPrev<CR>

  " =============== Git ==============
  nmap <leader>ci  <Plug>(coc-git-chunkinfo)

  " navigate git chunks when not in diff mode
  nnoremap <silent> <expr> [c &diff ? '[c' : ':execute "normal \<Plug>(coc-git-prevchunk)"<cr>'
  nnoremap <silent> <expr> ]c &diff ? ']c' : ':execute "normal \<Plug>(coc-git-nextchunk)"<cr>'

  " git/chunk revert
  nmap <leader>cr :<C-u>CocCommand git.chunkUndo<cr>

  nmap <silent> ]x  <Plug>(coc-git-nextconflict)
  nmap <silent> [x  <Plug>(coc-git-prevconflict)

  nmap <leader>kc <Plug>(coc-git-keepcurrent)
  nmap <leader>ki <Plug>(coc-git-keepincoming)
  nmap <leader>kb <Plug>(coc-git-keepboth)

  " Git status, show currently changed files
  nmap <leader>ga   :<c-u>CocCommand fzf-preview.GitActions<CR>

  " find symbol
  nnoremap <leader>fs :<C-u>CocFzfList symbols

  "=========== Other Code Actions =========
  " Symbol renaming.
  nmap <leader>re <Plug>(coc-rename)
endfunction

function! tw#coc#ShowDocumentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction
