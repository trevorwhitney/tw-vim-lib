local M = {}

local function mapKeys(which_key)
	local leaderKeymap = {
		["="] = { "<cmd>lua require('conform').format({ lsp_fallback=true })<cr>", "Format" },

		b = { "<cmd>Telescope buffers<cr>", "Find Buffer" },

		-- Diagnostics
		d = { "<cmd>Lspsaga show_line_diagnostics<cr>", "Line Diagnostics" },
		D = { "<cmd>lua require('trouble').toggle('document_diagnostics')<cr>", "Document Diagnostics" },

		-- Test
		t = {
			name = "Test",
			O = { ":Copen!<cr>", "Verbose Test Output" },

			f = { ":w<cr> :TestFile<cr>", "Test File" },
			l = { ":w<cr> :TestLast<cr>", "Test Last" },
			o = { ":Copen<cr>", "Test Output" },
			t = { ":w<cr> :TestNearest<cr>", "Test Nearest" },
			v = { ":TestVisit<cr>", "Open Last Run Test" },
		},

		-- Find
		f = { "<cmd>Telescope git_files<cr>", "Find File (Git)" },
		F = { "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>", "Find Grep" },

		p = {
			name = "Print",
			d = { "<cmd>lua require('refactoring').debug.printf({below = false})<CR>", "Print Debug Line" },
			v = { "<cmd>lua require('refactoring').debug.print_var()<CR>", "Print Var" },
			c = { "<cmd>lua require('refactoring').debug.cleanup()<CR>", "Cleanup Print Statements" },
		},

		-- Refactor
		r = {
			name = "Refactor",
			r = { "<cmd>lua require('telescope').extensions.refactoring.refactors()<CR>", "Refactor Menu" },
			p = { "<cmd>lua require('replacer').run()<cr>", "Replacer" },
			-- Inline variable works in both visual and normal mode
			i = { "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>", "Inline Variable" },
			-- Extract block only works in normal mode
			bl = { "<cmd>lua require('refactoring').refactor('Extract Block')<CR>", "Extract Block" },
			bf = { "<cmd>lua require('refactoring').refactor('Extract Block To File')<CR>", "Extract Block to File" },
		},

		R = { "<cmd>Telescope resume<cr>", "Resume Find" },
		["*"] = {
			"<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args({ default_text = vim.fn.expand('<cword>') })<cr>",
			"Find Grep (Current Word)",
		},

		["\\"] = { "<cmd>NvimTreeToggle<cr>", "NvimTree" },
		["|"] = { "<cmd>NvimTreeFindFile<cr>", "NvimTree (Current File)" },
	}

	which_key.register(leaderKeymap, {
		mode = "n",
		prefix = "<leader>",
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})

	vim.cmd("command! -nargs=* TelescopeLiveGrepRaw call v:lua.require('tw.telescope').live_grep_args(<q-args>)")
	local leaderVisualKeymap = {
		["*"] = {
			"\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
			"Search Current Selection",
		},
		p = {
			name = "Print",
			v = { "<cmd>lua require('refactoring').debug.print_var()<CR>", "Print Var" },
		},

		r = {
			name = "Refactor",
			-- Extract function supports only visual mode
			e = { "<cmd>lua require('refactoring').refactor('Extract Function')<CR>", "Extract Function" },
			f = {
				"<cmd>lua require('refactoring').refactor('Extract Function To File')<CR>",
				"Extract Function To File",
			},
			-- Inline variable works in both visual and normal mode
			i = { "<cmd>lua require('refactoring').refactor('Inline Variable')<CR>", "Inline Variable" },
			-- Extract variable supports only visual mode
			v = { "<cmd>lua require('refactoring').refactor('Extract Variable')<CR>", "Extract Variable" },
		},
		z = { ":'<,'>sort<cr>", "sort" },
	}

	which_key.register(leaderVisualKeymap, {
		mode = "v",
		prefix = "<leader>",
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})

	local noLeaderKeymap = {
		["\\"] = {
			name = "Windows",
			S = { "<cmd>Telescope git_status<cr>", "Git Status (Telescope)" },

			b = { "<cmd>Branches<cr>", "Branches" },
			c = { "<cmd>DapToggleConsole<cr>", "Dap Console" },
			d = { "<cmd>lua require('trouble').toggle('workspace_diagnostics')<cr>", "Workspace Diagnostics" },
			j = { "<cmd>Telescope jumplist<cr>", "Jump List" },
			l = { "<cmd>call ToggleLocationList()<cr>", "Location List" },
			m = { "<cmd>Telescope marks<cr>", "Marks" },
			o = { "<cmd>Outline<cr>", "Outline" },
			p = { "<cmd>pclose<cr>", "Close Preview" },
			q = { "<cmd>lua require('trouble').toggle('quickfix')<cr>", "Quickfix" },
			r = { "<cmd>call DapToggleRepl()<cr>", "Dap REPL" },
			s = { "<cmd>lua require('tw.config.Git').toggleGitStatus()<cr>", "Git Status" },
			t = { ":w<cr> <cmd>lua require('trouble').toggle()<cr>", "Toggle Trouble" },
		},

		-- Unimpaired style
		["]b"] = { ":bnext<cr>", "Next Buffer" },
		["[b"] = { ":bprevious<cr>", "Previous Buffer" },
		["]d"] = { "<cmd>lua require('trouble').next({skip_groups = true, jump = true, mode = 'document_diagnostics'})<cr>", "Next Diagnostic" },
		["[d"] = { "<cmd>lua require('trouble').previous({skip_groups = true, jump = true, mode = 'document_diagnostics'})<cr>", "Previous Diagnostic" },
		["]D"] = { "<cmd>lua require('trouble').next({skip_groups = true, jump = true, mode = 'workspace_diagnostics'})<cr>", "Next Workspace Diagnostic" },
		["[D"] = { "<cmd>lua require('trouble').previous({skip_groups = true, jump = true, mode = 'workspace_diagnostics'})<cr>", "Previous Workspace Diagnostic" },
		["]q"] = {
			"<cmd>lua require('trouble').next({skip_groups = true, jump = true, mode = 'quickfix'})<cr>",
			"Next Quickfix",
		},
		["[q"] = {
			"<cmd>lua require('trouble').previous({skip_groups = true, jump = true, mode = 'quickfix'})<cr>",
			"Previous Quickfix",
		},
		["[t"] = { ":tabprevious<cr>", "Previous Tab" },
		["]t"] = { ":tabnext<cr>", "Next Tab" },
		["[T"] = { ":tabfirst<cr>", "First Tab" },
		["]T"] = { ":tablast<cr>", "Last Tab" },
	}

	which_key.register(noLeaderKeymap, {
		mode = "n",
		prefix = nil,
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = true,
	})
end

function M.setup()
	local which_key = require("which-key")
	which_key.setup({
		window = {
			border = "single",
		},
	})

	mapKeys(which_key)
end

return M
