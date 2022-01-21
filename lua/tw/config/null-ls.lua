local null_ls = require("null-ls")
local home = vim.loop.os_getenv("HOME")

require("null-ls").setup({
	-- you must define at least one source for the plugin to work
	sources = {
		null_ls.builtins.code_actions.shellcheck,
		null_ls.builtins.code_actions.statix,
		null_ls.builtins.diagnostics.golangci_lint,
		null_ls.builtins.diagnostics.luacheck.with({
			extra_args = { "--globals", "vim", "run_sync" },
		}),
		null_ls.builtins.diagnostics.markdownlint.with({
			extra_args = { "--config", home .. "/.markdownlint.json" },
		}),
		null_ls.builtins.diagnostics.shellcheck,
		null_ls.builtins.diagnostics.statix,
		null_ls.builtins.diagnostics.vale,
		null_ls.builtins.diagnostics.vint,
		null_ls.builtins.diagnostics.write_good,
		null_ls.builtins.diagnostics.yamllint,
		null_ls.builtins.formatting.fixjson,
		null_ls.builtins.formatting.gofmt,
		null_ls.builtins.formatting.goimports,
		null_ls.builtins.formatting.nixfmt,
		null_ls.builtins.formatting.prettier,
		null_ls.builtins.formatting.shfmt,
		null_ls.builtins.formatting.stylua,
		null_ls.builtins.formatting.terraform_fmt,
		null_ls.builtins.formatting.trim_newlines,
		null_ls.builtins.formatting.trim_whitespace,
	},
})
