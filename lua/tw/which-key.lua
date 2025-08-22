local M = {}

local function mapKeys(wk)
	local keymap = {
		{
			"<leader>*",
			"<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>",
			desc = "Find Grep (Current Word)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>D",
			vim.diagnostic.open_float,
			desc = "Line Diagnostics",
			nowait = false,
			remap = false,
		},
		{
			"<leader>F",
			"<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>",
			desc = "Find Grep",
			nowait = false,
			remap = false,
		},
		{
			"<leader>R",
			"<cmd>Telescope resume<cr>",
			desc = "Resume Find",
			nowait = false,
			remap = false,
		},
		{
			"<leader>\\",
			"<cmd>NvimTreeToggle<cr>",
			desc = "NvimTree",
			nowait = false,
			remap = false,
		},
		{
			"<leader>b",
			"<cmd>Telescope buffers<cr>",
			desc = "Find Buffer",
			nowait = false,
			remap = false,
		},
		{
			"<leader>f",
			"<cmd>Telescope git_files<cr>",
			desc = "Find File (Git)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>i",
			group = "Config",
			nowait = false,
			remap = false,
		},
		{
			"<leader>r",
			group = "Refactor",
			nowait = false,
			remap = false,
		},
		{
			"<leader>rbf",
			"<cmd>lua require('refactoring').refactor('Extract Block To File')<CR>",
			desc = "Extract Block to File",
			nowait = false,
			remap = false,
		},
		{
			"<leader>rbl",
			"<cmd>lua require('refactoring').refactor('Extract Block')<CR>",
			desc = "Extract Block",
			nowait = false,
			remap = false,
		},
		{
			"<leader>ri",
			"<cmd>lua require('refactoring').refactor('Inline Variable')<CR>",
			desc = "Inline Variable",
			nowait = false,
			remap = false,
		},
		{
			"<leader>rp",
			"<cmd>lua require('replacer').run()<cr>",
			desc = "Replacer",
			nowait = false,
			remap = false,
		},
		{
			"<leader>rr",
			"<cmd>lua require('telescope').extensions.refactoring.refactors()<CR>",
			desc = "Refactor Menu",
			nowait = false,
			remap = false,
		},
		{
			"<leader>s",
			"<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
			desc = "Find Symbol",
			nowait = false,
			remap = false,
		},
		{
			"<leader>t",
			group = "Test",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tO",
			":Copen!<cr>",
			desc = "Verbose Test Output",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tf",
			":w<cr> :TestFile<cr>",
			desc = "Test File",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tl",
			":w<cr> :TestLast<cr>",
			desc = "Test Last",
			nowait = false,
			remap = false,
		},
		{
			"<leader>to",
			":Copen<cr>",
			desc = "Test Output",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tt",
			":w<cr> :TestNearest<cr>",
			desc = "Test Nearest",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tv",
			":TestVisit<cr>",
			desc = "Open Last Run Test",
			nowait = false,
			remap = false,
		},
		{
			"<leader>|",
			"<cmd>NvimTreeFindFile<cr>",
			desc = "NvimTree (Current File)",
			nowait = false,
			remap = false,
		},

		{
			"[T",
			":tabfirst<cr>",
			desc = "First Tab",
			nowait = true,
			remap = false,
		},
		{
			"]T",
			":tablast<cr>",
			desc = "Last Tab",
			nowait = true,
			remap = false,
		},
		{
			"]t",
			":tabnext<cr>",
			desc = "Next Tab",
			nowait = true,
			remap = false,
		},
		{
			"[t",
			":tabprevious<cr>",
			desc = "Previous Tab",
			nowait = true,
			remap = false,
		},
		{
			"[b",
			":bprevious<cr>",
			desc = "Previous Buffer",
			nowait = true,
			remap = false,
		},
		{
			"]b",
			":bnext<cr>",
			desc = "Next Buffer",
			nowait = true,
			remap = false,
		},
		{
			"[d",
			function()
				local trouble = require("trouble")
				if not trouble.is_open() then
					trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
					-- Small delay to ensure trouble is fully initialized
					vim.defer_fn(function()
						local t = require("trouble")
						t.prev({ skip_groups = true, jump = true })
					end, 100)
				else
					trouble.prev({ skip_groups = true, jump = true })
				end
			end,
			desc = "Previous Diagnostic",
			nowait = true,
			remap = false,
		},
		{
			"]d",
			function()
				local trouble = require("trouble")
				if not trouble.is_open() then
					trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
					-- Small delay to ensure trouble is fully initialized
					vim.defer_fn(function()
						local t = require("trouble")
						t.next({ skip_groups = true, jump = true })
					end, 100)
				else
					trouble.next({ skip_groups = true, jump = true })
				end
			end,
			desc = "Next Diagnostic",
			nowait = true,
			remap = false,
		},
		{
			"[q",
			function()
				local trouble = require("trouble")
				if not trouble.is_open() then
					trouble.toggle("quickfix")
					-- Small delay to ensure trouble is fully initialized
					vim.defer_fn(function()
						local t = require("trouble")
						t.prev({ skip_groups = true, jump = true })
					end, 100)
				else
					trouble.prev({ skip_groups = true, jump = true })
				end
			end,
			desc = "Previous Quickfix",
			nowait = true,
			remap = false,
		},
		{
			"]q",
			function()
				local trouble = require("trouble")
				if not trouble.is_open() then
					trouble.toggle("quickfix")
					-- Small delay to ensure trouble is fully initialized
					vim.defer_fn(function()
						local t = require("trouble")
						t.next({ skip_groups = true, jump = true })
					end, 100)
				else
					trouble.next({ skip_groups = true, jump = true })
				end
			end,
			desc = "Next Quickfix",
			nowait = true,
			remap = false,
		},

		{ "\\", group = "Windows", nowait = true, remap = false },
		{
			"\\D",
			function()
				local trouble = require("trouble")
				trouble.toggle("diagnostics")
			end,
			desc = "Workspace Diagnostics",
			nowait = true,
			remap = false,
		},
		{
			"\\d",
			function()
				local trouble = require("trouble")
				trouble.toggle({ mode = "diagnostics", filter = { buf = 0 } })
			end,
			desc = "Document Diagnostics",
			nowait = true,
			remap = false,
		},
		{ "\\O", "<cmd>AerialToggle!<cr>", desc = "Toggle Outline", nowait = true, remap = false },
		{ "\\S", "<cmd>Telescope git_status<cr>", desc = "Git Status (Telescope)", nowait = true, remap = false },
		{ "\\b", "<cmd>Telescope git_branches<cr>", desc = "Branches", nowait = true, remap = false },
		{ "\\j", "<cmd>Telescope jumplist<cr>", desc = "Jump List", nowait = true, remap = false },
		{ "\\l", "<cmd>call ToggleLocationList()<cr>", desc = "Location List", nowait = true, remap = false },
		{ "\\m", "<cmd>Telescope marks<cr>", desc = "Marks", nowait = true, remap = false },
		{
			"\\o",
			function()
				local telescope = require("telescope")
				telescope.extensions.aerial.aerial()
			end,
			desc = "Outline",
			nowait = true,
			remap = false,
		},
		{
			"\\p",
			"<cmd>pclose<cr>",
			desc = "Close Preview",
			nowait = true,
			remap = false,
		},
		{
			"\\q",
			function()
				local trouble = require("trouble")
				trouble.toggle("quickfix")
			end,
			desc = "Quickfix",
			nowait = true,
			remap = false,
		},
		{
			"\\r",
			function()
				-- get current buffer and window
				local buf = vim.api.nvim_get_current_buf()
				local win = vim.api.nvim_get_current_win()

				-- create a new split for the repl
				vim.cmd("split")

				-- spawn repl and set the context to our buffer
				require("neorepl").new({
					lang = "lua",
					buffer = buf,
					window = win,
				})
				-- resize repl window and make it fixed height
				vim.cmd("resize 10 | setl winfixheight")
			end,
			desc = "Neovim REPL",
			nowait = true,
			remap = false,
		},
		{
			"\\s",
			"<cmd>lua require('tw.git').toggleGitStatus()<cr>",
			desc = "Git Status",
			nowait = true,
			remap = false,
		},

		{
			mode = { "v" },
			{
				"<leader>*",
				"\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
				desc = "Search Current Selection",
				nowait = false,
				remap = false,
			},
			{
				"<leader>r",
				group = "Refactor",
				nowait = false,
				remap = false,
			},
			{
				"<leader>re",
				"<cmd>lua require('refactoring').refactor('Extract Function')<CR>",
				desc = "Extract Function",
				nowait = false,
				remap = false,
			},
			{
				"<leader>rf",
				"<cmd>lua require('refactoring').refactor('Extract Function To File')<CR>",
				desc = "Extract Function To File",
				nowait = false,
				remap = false,
			},
			{
				"<leader>ri",
				"<cmd>lua require('refactoring').refactor('Inline Variable')<CR>",
				desc = "Inline Variable",
				nowait = false,
				remap = false,
			},
			{
				"<leader>rv",
				"<cmd>lua require('refactoring').refactor('Extract Variable')<CR>",
				desc = "Extract Variable",
				nowait = false,
				remap = false,
			},
			{
				"<leader>s",
				"\"sy:TelescopeDynamicWorkspaceSymbol <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
				desc = "Search Current Symbol",
				nowait = false,
				remap = false,
			},
			{
				"<leader>z",
				":'<,'>sort<cr>",
				desc = "sort",
				nowait = false,
				remap = false,
			},
		},
	}

	wk.add(keymap)

	vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
	vim.cmd(
		"command! -nargs=* TelescopeDynamicWorkspaceSymbol call v:lua.require('tw.telescope').dynamic_workspace_symbols(<q-args>)"
	)
end

local function vimMappings()
	local cmd = vim.cmd
	cmd.ca("Qa", "qa")
	cmd.ca("QA", "qa")
	cmd.ca("q", "q")
	cmd.ca("W", "w")
	cmd.ca("WQ", "wq")
	cmd.ca("Wq", "wq")
	cmd.ca("WQA", "wqa")
	cmd.ca("WQa", "wqa")
	cmd.ca("Wqa", "wqa")
	local api = vim.api
	api.nvim_create_user_command("Qa", ":qa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("QA", ":qa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("Q", ":q", { bang = true, nargs = 0 })
	api.nvim_create_user_command("Wq", ":wq", { bang = true, nargs = 0 })
	api.nvim_create_user_command("WQ", ":wq", { bang = true, nargs = 0 })
	api.nvim_create_user_command("WQA", ":wqa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("WQa", ":wqa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("Wqa", ":wqa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("W", ":w", { bang = true, nargs = 0 })

	local keymap = vim.keymap
	keymap.set("n", "<C-q>", "<Nop>", { noremap = true })
	keymap.set("x", "il", "g_o^", { noremap = true })
	keymap.set("o", "il", ":normal vil<cr>", { noremap = true })
	keymap.set("x", "al", "$o^", { noremap = true })
	keymap.set("o", "al", ":normal val<cr>", { noremap = true })

	keymap.set("i", "jj", "<Esc>", { noremap = true, nowait = true })
	keymap.set("c", "w!!", ":w !sudo tee > /dev/null %")

	keymap.set("i", "<C-o>", "<C-x><C-o>", { noremap = true })

	keymap.set("n", "<C-j>", "<C-W><C-J>", { noremap = true })
	keymap.set("n", "<C-k>", "<C-W><C-K>", { noremap = true })
	keymap.set("n", "<C-l>", "<C-W><C-L>", { noremap = true })
	keymap.set("n", "<C-h>", "<C-W><C-H>", { noremap = true })
	keymap.set("n", "<C-w>q", ":window close<cr>", { noremap = true })

	-- ====== Readline / RSI =======
	keymap.set("i", "<c-k>", "<c-o>D", { noremap = true })
	keymap.set("c", "<c-k>", "<c-\\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<cr>", { noremap = true })
	-- ====== Terminal =======
	keymap.set("t", "jj", "<C-\\><C-n>", { noremap = true })

	-- ====== Tmux-Navigator =======
	-- This is done manually instead of automatically via the plugin to make it work with terminals
	-- The default mappings are disabled in packer.lua
	keymap.set("n", "<C-j>", function()
		vim.cmd("update")
		vim.cmd("TmuxNavigateDown")
	end, { noremap = true, silent = true })
	keymap.set("n", "<C-k>", function()
		vim.cmd("update")
		vim.cmd("TmuxNavigateUp")
	end, { noremap = true, silent = true })
	keymap.set("n", "<C-h>", function()
		vim.cmd("update")
		vim.cmd("TmuxNavigateLeft")
	end, { noremap = true, silent = true })
	keymap.set("n", "<C-l>", function()
		vim.cmd("update")
		vim.cmd("TmuxNavigateRight")
	end, { noremap = true, silent = true })
	keymap.set("t", "<C-j>", "<C-\\><C-n><C-W><C-J>", { noremap = true })
	keymap.set("t", "<C-k>", "<C-\\><C-n><C-W><C-k>", { noremap = true })
	keymap.set("t", "<C-h>", "<C-\\><C-n><C-W><C-h>", { noremap = true })
	keymap.set("t", "<C-l>", "<C-\\><C-n><C-W><C-l>", { noremap = true })
end

function M.setup()
	local which_key = require("which-key")
	which_key.setup({
		win = {
			border = "single",
		},
	})

	mapKeys(which_key)
	vimMappings()
end

return M
