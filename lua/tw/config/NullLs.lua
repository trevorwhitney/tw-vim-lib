local M = {}

function M.setup()
  local null_ls = require("null-ls")
  local lsp = require("tw.config.Lsp")
  local home = vim.loop.os_getenv("HOME")

  require("null-ls").setup({
    on_attach = lsp.on_attach,

    -- you must define at least one source for the plugin to work
    sources = {
      null_ls.builtins.code_actions.eslint_d,
      null_ls.builtins.code_actions.shellcheck.with({
        extra_args = { "-x", "-o", "all" },
      }),
      -- null_ls.builtins.code_actions.refactoring,
      null_ls.builtins.code_actions.statix,
      null_ls.builtins.diagnostics.eslint_d,
      null_ls.builtins.diagnostics.golangci_lint,
      null_ls.builtins.diagnostics.luacheck.with({
        extra_args = { "--globals", "vim", "run_sync" },
      }),
      null_ls.builtins.diagnostics.markdownlint.with({
        extra_args = { "--config", home .. "/.markdownlint.json" },
      }),
      null_ls.builtins.diagnostics.shellcheck.with({
        extra_args = { "-x", "-o", "all" },
      }),
      null_ls.builtins.diagnostics.statix,
      null_ls.builtins.diagnostics.tsc,
      -- null_ls.builtins.diagnostics.vint,
      null_ls.builtins.diagnostics.yamllint,
      null_ls.builtins.formatting.eslint_d,
      null_ls.builtins.formatting.fixjson,
      null_ls.builtins.formatting.gofmt,
      null_ls.builtins.formatting.goimports,
      null_ls.builtins.formatting.nixpkgs_fmt,
      null_ls.builtins.formatting.prettier,
      null_ls.builtins.formatting.shfmt,
      null_ls.builtins.formatting.stylua,
      null_ls.builtins.formatting.terraform_fmt,
      null_ls.builtins.formatting.trim_newlines,
      null_ls.builtins.formatting.trim_whitespace,
    },
  })
end

return M
