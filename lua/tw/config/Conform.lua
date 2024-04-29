local M = {}
local conform_format = require("conform").format

local function format(bufnr, options)
	local options = options or {}
	local ignore_filetypes = {
		"Trouble",
		"dap-repl",
		"dapui_console",
		"fugitive",
		"lua",
	}
	if vim.tbl_contains(ignore_filetypes, vim.bo[bufnr].filetype) then
		local opts = vim.tbl_deep_extend("force", { timeout_ms = 500 }, options)
		conform_format(opts)
		return opts
	end

	local lines = vim.fn.system("git diff --unified=0 " .. vim.fn.bufname(bufnr)):gmatch("[^\n\r]+")
	local ranges = {}
	for line in lines do
		if line:find("^@@") then
			local line_nums = line:match("%+.- ")
			if line_nums:find(",") then
				local _, _, first, second = line_nums:find("(%d+),(%d+)")
				table.insert(ranges, {
					start = { tonumber(first), 0 },
					["end"] = { tonumber(first) + tonumber(second), 0 },
				})
			else
				local first = tonumber(line_nums:match("%d+"))
				table.insert(ranges, {
					start = { first, 0 },
					["end"] = { first + 1, 0 },
				})
			end
		end
	end

	for _, range in pairs(ranges) do
		local opts = vim.tbl_deep_extend("force", { range = range, timeout_ms = 500 }, options)
		conform_format(opts)
	end

	return vim.tbl_deep_extend("force", { timeout_ms = 500 }, options)
end

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
			go = { "golines", "goimports", "gofumpt" },
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
		format_on_save = format,
	})
end

function M.setup(use_eslint_daemon)
	configure(use_eslint_daemon)
end

function M.format(options)
	local bufnr = vim.api.nvim_get_current_buf()
	format(bufnr, options)
end

return M
