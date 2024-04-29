local M = {}

local function mapKeys(which_key)
	local trouble = require("trouble")
  local format = require("tw.config.Conform").format
	local leaderKeymap = {
		["="] = { function() 
			vim.cmd("update")
      format({ lsp_fallback=false })
    end, "Format" },

		b = { "<cmd>Telescope buffers<cr>", "Find Buffer" },

		-- Diagnostics
		D = { "<cmd>Lspsaga show_line_diagnostics<cr>", "Line Diagnostics" },

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
		s = { "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", "Find Symbol" },

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
	vim.cmd(
		"command! -nargs=* TelescopeDynamicWorkspaceSymbol call v:lua.require('tw.telescope').dynamic_workspace_symbols(<q-args>)"
	)

	vim.api.nvim_create_user_command("FormatSelection", function(args)
		local range = nil
		if args.count ~= -1 then
			local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
			range = {
				start = { args.line1, 0 },
				["end"] = { args.line2, end_line:len() },
			}
		end
		require("conform").format({ async = true, lsp_fallback = true, range = range })
	end, { range = true })

	local leaderVisualKeymap = {
		["*"] = {
			"\"sy:TelescopeLiveGrepRaw <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
			"Search Current Selection",
		},
		["="] = { "<cmd>FormatSelection<cr>", "Format" },

		s = {
			"\"sy:TelescopeDynamicWorkspaceSymbol <C-R>=v:lua.require('tw.telescope').current_selection(@s)<cr><cr>",
			"Search Current Symbol",
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
			D = {
				function()
					trouble.toggle("workspace_diagnostics")
				end,
				"Workspace Diagnostics",
			},
			O = { "<cmd>OutlineClose<cr>", "Close Outline" },
			S = { "<cmd>Telescope git_status<cr>", "Git Status (Telescope)" },

			b = { "<cmd>Telescope git_branches<cr>", "Branches" },
			c = { "<cmd>DapToggleConsole<cr>", "Dap Console" },
			d = {
				function()
					trouble.toggle("document_diagnostics")
				end,
				"Document Diagnostics",
			},
			j = { "<cmd>Telescope jumplist<cr>", "Jump List" },
			l = { "<cmd>call ToggleLocationList()<cr>", "Location List" },
			m = { "<cmd>Telescope marks<cr>", "Marks" },
			o = {
				function()
					local outline = require("outline")

					if outline.is_open() then
						if outline.has_focus() then
							outline.close()
						else
							outline.follow_cursor()
						end
					else
						outline.open()
						outline.follow_cursor()
					end
				end,
				"Outline",
			},
			p = { "<cmd>pclose<cr>", "Close Preview" },
			q = {
				function()
					trouble.toggle("quickfix")
				end,
				"Quickfix",
			},
			r = { "<cmd>call DapToggleRepl()<cr>", "Dap REPL" },
			s = { "<cmd>lua require('tw.config.Git').toggleGitStatus()<cr>", "Git Status" },
			t = {
				function()
					trouble.toggle()
				end,
				"Toggle Trouble",
			},
		},

		-- Unimpaired style
		["]b"] = { ":bnext<cr>", "Next Buffer" },
		["[b"] = { ":bprevious<cr>", "Previous Buffer" },

		-- Trouble / Quickfix
		["]q"] = {
			function()
				if not trouble.is_open() then
					trouble.toggle()
				end

				trouble.next({ skip_groups = true, jump = true })
			end,
			"Next Quickfix",
		},
		["[q"] = {
			function()
				if not trouble.is_open() then
					trouble.toggle()
				end

				trouble.previous({ skip_groups = true, jump = true })
			end,
			"Previous Quickfix",
		},

		-- LSP references
		["]r"] = {
			function()
				trouble.open("lsp_references")
				trouble.next({ skip_groups = true, jump = true, mode = "lsp_references" })
			end,
			"Next Reference",
		},
		["[r"] = {
			function()
				trouble.open("ls_references")
				trouble.previous({ skip_groups = true, jump = true, mode = "lsp_references" })
			end,
			"Previous Reference",
		},

		-- Tabs
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

local function vimMappings()
	local cmd = vim.cmd
	cmd.ca("Qa", "qa")
	cmd.ca("QA", "qa")
	cmd.ca("q", "q")
	cmd.ca("W", "w")
	cmd.ca("WQ", "wq")
	cmd.ca("Wq", "wq")

	local api = vim.api
	api.nvim_create_user_command("Qa", ":qa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("QA", ":qa", { bang = true, nargs = 0 })
	api.nvim_create_user_command("Q", ":q", { bang = true, nargs = 0 })
	api.nvim_create_user_command("Wq", ":wq", { bang = true, nargs = 0 })
	api.nvim_create_user_command("WQ", ":wq", { bang = true, nargs = 0 })
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

	keymap.set("n", "<C-J>", "<C-W><C-J>", { noremap = true })
	keymap.set("n", "<C-K>", "<C-W><C-K>", { noremap = true })
	keymap.set("n", "<C-L>", "<C-W><C-L>", { noremap = true })
	keymap.set("n", "<C-H>", "<C-W><C-H>", { noremap = true })
	keymap.set("n", "<C-w>q", ":window close<cr>", { noremap = true })

	-- ====== Readline / RSI =======
	keymap.set("i", "<c-k>", "<c-o>D", { noremap = true })
	keymap.set("c", "<c-k>", "<c-\\>e getcmdpos() == 1 ? '' : getcmdline()[:getcmdpos()-2]<cr>", { noremap = true })
end

function M.setup()
	local which_key = require("which-key")
	which_key.setup({
		window = {
			border = "single",
		},
	})

	mapKeys(which_key)
	vimMappings()
end

return M
