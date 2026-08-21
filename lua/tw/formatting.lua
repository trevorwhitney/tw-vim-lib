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
local function format_ranges_sequentially(ranges, index, opts, done)
	local range = ranges[index]
	if range == nil then
		done()
		return
	end

	local opt = vim.tbl_deep_extend("force", { range = range }, opts)
	local fmt_start = vim.uv.hrtime()
	require("conform").format(opt, function(err, _)
		local fmt_ms = (vim.uv.hrtime() - fmt_start) / 1e6
		log.debug(string.format("format: conform range %d took %.1fms (err=%s)", index, fmt_ms, tostring(err)))
		format_ranges_sequentially(ranges, index + 1, opts, done)
	end)
end

-- git runs off the main loop; a stale .git/index.lock or a slow repo can no
-- longer freeze the UI. Ranges are computed in the callback.
local function format_diff_ranges(argv, cwd, opts, fallback_argv, done)
	local git_start = vim.uv.hrtime()
	vim.system(
		argv,
		{ text = true, cwd = cwd },
		vim.schedule_wrap(function(result)
			local git_ms = (vim.uv.hrtime() - git_start) / 1e6
			log.debug(string.format("format: git diff took %.1fms (code=%d)", git_ms, result.code or -1))

			if result.code ~= 0 then
				if fallback_argv then
					format_diff_ranges(fallback_argv, cwd, opts, nil, done)
				else
					done()
				end
				return
			end

			local ranges = parse_ranges(result.stdout or "")
			if not next(ranges) then
				done()
				return
			end

			format_ranges_sequentially(ranges, 1, opts, done)
		end)
	)
end

local function format(bufnr, options, on_done)
	local done = on_done or function() end
	local opts = options or {}
	opts = vim.tbl_deep_extend("force", opts, {
		async = true,
		lsp_format = "first",
	})

	local buf_ft = vim.bo[bufnr].filetype
	if vim.tbl_contains(ignore_filetypes, buf_ft) then
		done()
		return
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if filename == "" then
		done()
		return
	end
	local cwd = vim.fs.dirname(filename)

	vim.system(
		{ "git", "ls-files", "--error-unmatch", "--", filename },
		{ text = true, cwd = cwd },
		vim.schedule_wrap(function(tracked)
			-- An untracked file is entirely this branch's work and has no base
			-- revision to diff against, so format all of it.
			if tracked.code ~= 0 then
				require("conform").format(opts, done)
				return
			end

			-- Diff against the merge-base rather than HEAD: HEAD misses anything
			-- already committed on this branch, which is exactly how unformatted
			-- code reaches a PR. The merge-base keeps hunks limited to work this
			-- branch introduced, so untouched lines are never rewritten.
			format_diff_ranges(
				{ "git", "diff", "--unified=0", "--merge-base", "origin/HEAD", "--", filename },
				cwd,
				opts,
				{ "git", "diff", "--unified=0", "--", filename },
				done
			)
		end)
	)
end

local exiting = false
local formatting = {}

-- Formatting happens after the write, not before it, because the hunk ranges
-- come from `git diff` against the file on disk. Conform's own format_on_save
-- is whole-buffer only, so it would rewrite lines this branch never touched.
local function format_after_save(bufnr)
	if exiting or formatting[bufnr] then
		return
	end
	formatting[bufnr] = true

	format(bufnr, {}, function()
		if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("silent keepjumps noautocmd write")
			end)
		end
		formatting[bufnr] = nil
	end)
end

local function watchSaves()
	local aug = vim.api.nvim_create_augroup("TwFormatting", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = aug,
		pattern = "*",
		callback = function(args)
			if vim.bo[args.buf].buftype ~= "" then
				return
			end
			format_after_save(args.buf)
		end,
	})

	-- An async format landing mid-exit would edit a buffer Neovim is already
	-- tearing down, so stop starting them once exit begins. `:wq` consequently
	-- writes unformatted; `:w` then `:q` formats.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = aug,
		pattern = "*",
		callback = function()
			exiting = true
		end,
	})
end

local function configure()
	local formatters_by_ft = {
		bash = { "shfmt", "shellcheck" },
		-- these are all broken, do they not work with partial ranges?
		-- go = { "goimports", "gofmt", "gofumpt", "golines" },
		-- eslint_d is deliberately absent: it dies on any project using eslint 10
		-- (it mutates `chalk.level`, and eslint 10 dropped chalk, so the require
		-- resolves an ESM chalk 5 whose namespace is frozen). Because
		-- stop_after_first only checks whether the binary exists, leaving it here
		-- shadows prettier everywhere instead of falling through.
		javascript = { "prettierd", "prettier", stop_after_first = true },
		json = { "prettierd", "fixjson" },
		jsonnet = { "jsonnetfmt" },
		markdown = { "prettierd", "markdownlint" },
		nix = { "nixpkgs_fmt" },
		sh = { "shfmt", "shellcheck" },
		terraform = { "terraform_fmt" },
		typescript = { "prettierd", "prettier", stop_after_first = true },
		lua = { "stylua", lsp_format = "fallback" },

		["_"] = { "trim_whitespace", "trim_newlines" },
	}
	require("conform").setup({
		log_level = vim.log.levels.DEBUG,
		formatters_by_ft = formatters_by_ft,
		default_format_opts = {
			lsp_format = "first",
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
					-- Writing triggers the BufWritePost formatter, so only format
					-- directly when there is nothing to write. Formatting always needs
					-- the buffer on disk first: hunks come from `git diff`.
					if vim.bo.modified then
						vim.cmd("update")
					else
						M.format()
					end
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
	watchSaves()
	mapKeys()
end

function M.format(options)
	local opts = options or {}
	local bufnr = vim.api.nvim_get_current_buf()
	format(bufnr, opts)
end

return M
