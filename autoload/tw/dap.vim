function! tw#dap#MapKeys() abort
  nnoremap <silent> <F9> <cmd>lua require("dap").continue()<cr>
  nnoremap <silent> <F8> <cmd>lua require("dap").step_over()<cr>
  nnoremap <silent> <F7> <cmd>lua require("dap").step_into()<cr>
  nnoremap <silent> <F6> <cmd>lua require("dap").step_out()<cr>

  nnoremap <silent> <leader>b <cmd>lua require("dap").toggle_breakpoint()<cr>
  nnoremap <silent> <leader>B <cmd>lua require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))<cr>
  nnoremap <silent> <leader>lp <cmd>lua require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))<cr>
  nnoremap <silent> <leader>dr <cmd>lua require("dap").repl.open()<cr>
  nnoremap <silent> <leader>dl <cmd>lua require("dap").run_last()<cr>
  nnoremap <silent> <leader>du <cmd>lua require("dapui").toggle()<cr>

  vnoremap <leader>d* <Cmd>lua require("dapui").eval()<CR>
endfunction
