local M = {}

local function mapKeys(which_key)
	local leaderKeymap = {
		["="] = { "<cmd>lua require('conform').format({ lsp_fallback=true })<cr>", "Format" },

		b = { "<cmd>Telescope buffers<cr>", "Find Buffer" },

		-- Test
		t = {
			name = "Test",
			-- 	-- t = { ":w<cr> :TestNearest<cr>", "Test Nearest" },
			-- 	-- l = { ":w<cr> :TestLast<cr>", "Test Last" },
			-- 	-- f = { ":w<cr> :TestFile<cr>", "Test File" },
			f = { ":w<cr> <cmd>lua require('neotest').run.run(vim.fn.expand(\"%\"))<cr>", "Test File" },
			l = { ":w<cr> <cmd>lua require('neotest').run.run_last()<cr>", "Test Last" },
			n = { "<cmd>lua require('neotest').jump.next({ status = 'failed' })<cr>", "Next Failed" },
			o = { ":w<cr> <cmd>lua require('neotest').output_panel.toggle()<cr>", "Test Output" },
			O = { ":Copen!<cr>", "Verbose Test Output" },
			p = { "<cmd>lua require('neotest').jump.prev({ status = 'failed' })<cr>", "Previous Failed" },
			s = { ":w<cr> <cmd>lua require('neotest').summary.toggle()<cr>", "Test Summary" },
			t = { ":w<cr> <cmd>lua require('neotest').run.run()<cr>", "Test Nearest" },
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
			-- d = { "<cmd>Telescope diagnostics<CR>", "Diagnostic List" },
			d = { "<cmd>lua require('trouble').toggle('document_diagnostics')<cr>", "Diagnostic List" },
			D = { "<cmd>lua require('trouble').toggle('workspace_diagnostics')<cr>", "Workspace Diagnostic List" },
			j = { "<cmd>Telescope jumplist<cr>", "Jump List" },
			l = { "<cmd>call ToggleLocationList()<cr>", "Location List" },
			m = { "<cmd>Telescope marks<cr>", "Marks" },
			-- o = { "<cmd>Telescope lsp_document_symbols<cr>", "Outline" },
			o = { "<cmd>Outline<cr>", "Outline" },
			p = { "<cmd>pclose<cr>", "Close Preview" },
			q = { "<cmd>lua require('trouble').toggle('quickfix')<cr>", "Quickfix" },
			r = { "<cmd>call DapToggleRepl()<cr>", "Dap REPL" },
			s = { "<cmd>Git<cr>", "Git Status" },
			-- t = { "<cmd>Telescope tagstack<cr>", "Tag Stack" },
			t = { ":w<cr> <cmd>lua require('trouble').toggle()<cr>", "Toggle Trouble" },
		},
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
