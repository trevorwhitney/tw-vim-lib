local M = {}

function M.configure_lsp(on_attach, capabilities)
  return {
    capabilities = capabilities,
    flags = {
      debounce_text_changes = 150,
    },
    on_attach = function(client, bufnr)
      on_attach(client, bufnr)

      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = bufnr,
        command = "EslintFixAll",
      })
    end,
  }
end


return M
