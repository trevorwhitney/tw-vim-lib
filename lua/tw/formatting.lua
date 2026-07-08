local M = {}

local log = require("tw.log")

local ignore_filetypes = {
	"Trouble",
	"dap-repl",
	"dapui_console",
	"fugitive",
}

local function parse_ranges(diff_output)
	local ranges = {}
	for line in diff_output:gmatch("[^\n\r]+") do
		if line:find("^@@") then
			local line_nums = line:match("%+.- ")
			if line_nums:find(",") then
				local _, _, first, second = line_nums:find("(%d+),(%d+)")
				first = tonumber(first)
				second = tonumber(second)
				if first and second then
					local end_line_pos = first + second - 1
					local end_line = vim.api.nvim_buf_get_lines(0, end_line_pos - 1, end_line_pos, true)[1]
					table.insert(ranges, {
						start = { first, 0 },
						["end"] = { end_line_pos, end_line:len() - 1 },
					})
				end
			else
				local first = tonumber(line_nums:match("%d+"))
				if first then
					local end_line = vim.api.nvim_buf_get_lines(0, first, first + 1, true)[1]
					table.insert(ranges, {
						start = { first, 0 },
						["end"] = { first + 1, end_line:len() - 1 },
					})
				end
			end
		end
	end
	return ranges
end

-- Format ranges one at a time. Each conform call is async (won't block the
-- UI), but the next range only starts after the previous completes so their
-- buffer edits can't clobber each other's line offsets.
local function format_ranges_sequentially(ranges, index, opts)
	local range = ranges[index]
	if range == nil then
		return
	end

	local opt = vim.tbl_deep_extend("force", { range = range }, opts)
	local fmt_start = vim.uv.hrtime()
	require("conform").format(opt, function(err, _)
		local fmt_ms = (vim.uv.hrtime() - fmt_start) / 1e6
		log.debug(string.format("format: conform range %d took %.1fms (err=%s)", index, fmt_ms, tostring(err)))
		format_ranges_sequentially(ranges, index + 1, opts)
	end)
end

local function format(bufnr, options)
	local opts = options or {}
	opts = vim.tbl_deep_extend("force", opts, {
		async = true,
		lsp_format = "first",
	})

	local buf_ft = vim.bo[bufnr].filetype
	if vim.tbl_contains(ignore_filetypes, buf_ft) then
		return
	end

	-- `git diff` runs off the main loop; a stale .git/index.lock or a slow
	-- repo can no longer freeze the UI. Ranges are computed in the callback.
	local git_start = vim.uv.hrtime()
	vim.system(
		{ "git", "diff", "--unified=0", vim.fn.bufname(bufnr) },
		{ text = true },
		vim.schedule_wrap(function(result)
			local git_ms = (vim.uv.hrtime() - git_start) / 1e6
			log.debug(string.format("format: git diff took %.1fms (code=%d)", git_ms, result.code or -1))

			if result.code ~= 0 then
				return
			end

			local ranges = parse_ranges(result.stdout or "")
			if not next(ranges) then
				return
			end

			format_ranges_sequentially(ranges, 1, opts)
		end)
	)
end

local function configure()
	local formatters_by_ft = {
		bash = { "shfmt", "shellcheck" },
		-- these are all broken, do they not work with partial ranges?
		-- go = { "goimports", "gofmt", "gofumpt", "golines" },
		javascript = { "eslint_d", "prettierd", "eslint", "prettier", stop_after_first = true },
		json = { "prettierd", "fixjson" },
		jsonnet = { "jsonnetfmt" },
		markdown = { "prettierd", "markdownlint" },
		nix = { "nixpkgs_fmt" },
		sh = { "shfmt", "shellcheck" },
		terraform = { "terraform_fmt" },
		typescript = { "eslint_d", "prettierd", "eslint", "prettier", stop_after_first = true },
		lua = { "stylua", lsp_format = "fallback" },

		["_"] = { "trim_whitespace", "trim_newlines" },
	}
	require("conform").setup({
		log_level = vim.log.levels.DEBUG,
		formatters_by_ft = formatters_by_ft,
		default_format_opts = {
			lsp_format = "first",
		},
		-- Bound the on-save format so a slow/busy gopls can't freeze the editor
		-- longer than this. Beyond the timeout conform bails and the save proceeds.
		format_on_save = {
			lsp_format = "first",
			timeout_ms = 1000,
		},
	})
end

local function mapKeys()
	local wk = require("which-key")
	local keymap = {
		-- Formatting
		{
			mode = { "v", "x" },
			{
				"<leader>=",
				function()
					vim.cmd("update")
					local bufnr = vim.api.nvim_get_current_buf()
					local buf_ft = vim.bo[bufnr].filetype

					-- Go formatters are broken, I think because they don't support partial ranges.
					-- So conditionally run golines for a specifically selected range, otherwise rely on lsp formatting
					if buf_ft == "go" then
						require("conform").format({ async = false, lsp_format = "first", formatters = { "golines" } })
						return
					end

					require("conform").format({ async = false, lsp_format = "first" })
				end,
				desc = "Format",
				nowait = true,
				remap = false,
			},
		},
		{
			mode = { "n" },
			{
				"<leader>=",
				function()
					vim.cmd("update")
					M.format()
				end,
				desc = "Format",
				nowait = true,
				remap = false,
			},
			{
				"<leader>+",
				function()
					vim.cmd("update")
					require("conform").format({ async = false, lsp_format = "first" })
				end,
				desc = "Format",
				nowait = true,
				remap = false,
			},
		},
	}

	wk.add(keymap)
end
function M.setup()
	configure()
	mapKeys()
end

function M.format(options)
	local opts = options or {}
	local bufnr = vim.api.nvim_get_current_buf()
	format(bufnr, opts)
end

return M
