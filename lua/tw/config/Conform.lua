local M = {}

local function configure(use_eslint_daemon)
	local set = vim.opt
	set.formatexpr = "v:lua.require'conform'.formatexpr()"

	local eslint = { "eslint" }
	if use_eslint_daemon then
		eslint = { "eslint_d" }
	end

	require("conform").setup({
		formatters_by_ft = {
			bash = { "shfmt", "shellcheck" },
			go = { "gofmt", "goimports" },
			javascript = { eslint, { "prettierd", "prettier" } },
			json = { { "prettierd", "prettier" }, "fixjson" },
			jsonnet = { "jsonnetfmt" },
			lua = { "stylua" },
			markdown = { { "prettierd", "prettier" }, "markdownlint" },
			nix = { "nixpkgs_fmt" },
			sh = { "shfmt", "shellcheck" },
			terraform = { "terraform_fmt" },
			typescript = { eslint, { "prettierd", "prettier" } },

			["*"] = { "codespell" },
			["_"] = { "trim_whitespace", "trim_newlines" },
		},
		format_on_save = {
			lsp_fallback = true,
			timeout_ms = 500,
		},
	})
end

function M.setup(use_eslint_daemon)
	configure(use_eslint_daemon)
end

return M
