local M = {}

function M.setup(use_eslint_daemon)
  local null_ls = require("null-ls")
  local lsp = require("tw.config.Lsp")
  local home = vim.loop.os_getenv("HOME")

  local config = {
    on_attach = lsp.on_attach,
    debug = true,

    -- you must define at least one source for the plugin to work
    sources = {
      null_ls.builtins.code_actions.shellcheck.with({
        extra_args = { "-x", "-o", "all" },
      }),
      -- null_ls.builtins.code_actions.refactoring,
      null_ls.builtins.code_actions.statix,
      null_ls.builtins.diagnostics.golangci_lint.with({
        timeout = 30000,
      }),
      -- included in golangci-lint, but sometimes nice to have
      -- null_ls.builtins.diagnostics.revive.with({
      --   timeout = 10000,
      -- }),
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
      null_ls.builtins.diagnostics.yamllint,
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
  }

  if use_eslint_daemon then
    for _, source in ipairs({
      null_ls.builtins.code_actions.eslint_d,
      null_ls.builtins.diagnostics.eslint_d,
      null_ls.builtins.formatting.eslint_d,
    }) do
      table.insert(config.sources, source)
    end
  else
    for _, source in ipairs({
        null_ls.builtins.code_actions.eslint,
        null_ls.builtins.diagnostics.eslint,
        null_ls.builtins.formatting.eslint,
      }) do
        table.insert(config.sources, source)
    end
  end

  require("null-ls").setup(config)
end

return M
