local M = {}
local conform_format = require("conform").format

local function format(bufnr, options)
	local options = options or {}
	options = vim.tbl_deep_extend("force", options, { async = true })
	local ignore_filetypes = {
		"Trouble",
		"dap-repl",
		"dapui_console",
		"fugitive",
	}
	local buf_ft = vim.bo[bufnr].filetype
	if vim.tbl_contains(ignore_filetypes, buf_ft) then
		return
	end

  -- only use golines when formatting changed lines
	if buf_ft == "go" then
		options = vim.tbl_deep_extend(
			"force",
			options,
			{ formatters = { "golines", "goimports", "gofumpt", "trim_whitespace", "trim_newlines" } }
		)
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
		local opts = vim.tbl_deep_extend("force", { range = range }, options)
		conform_format(opts)
	end

	return
end

local function configure(use_eslint_daemon)
	local set = vim.opt
	set.formatexpr = "v:lua.require'conform'.formatexpr()"

	local eslint = { "eslint" }
	if use_eslint_daemon then
		eslint = { "eslint_d" }
	end

	local formatters_by_ft = {
		bash = { "shfmt", "shellcheck" },
		go = { "goimports", "gofumpt" },
		javascript = { eslint, { "prettierd", "prettier" } },
		json = { { "prettierd", "prettier" }, "fixjson" },
		jsonnet = { "jsonnetfmt" },
		lua = { "stylua" },
		markdown = { { "prettierd", "prettier" }, "markdownlint" },
		nix = { "nixpkgs_fmt" },
		sh = { "shfmt", "shellcheck" },
		terraform = { "terraform_fmt" },
		typescript = { eslint, { "prettierd", "prettier" } },

		["_"] = { "trim_whitespace", "trim_newlines" },
	}
	require("conform").setup({
		formatters_by_ft = formatters_by_ft,
		format_on_save = function(bufnr)
			local buf_ft = vim.bo[bufnr].filetype
			local formatters = { "codespell", "trim_whitespace", "trim_newlines" }

			if buf_ft then
				local formatters_for_ft = formatters_by_ft[buf_ft]
				if formatters_for_ft ~= nil then
					for _, v in ipairs(formatters_for_ft) do
						table.insert(formatters, v)
					end
				end
			end

			return {
				timeout_ms = 500,
				lsp_fallback = true,
				formatters = formatters,
			}
		end,
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
