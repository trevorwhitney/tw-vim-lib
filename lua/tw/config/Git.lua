local M = {}

local function setup()
	require("gitsigns").setup({
		current_line_blame = true,
		-- highlight numbers instead of using the sign column
		signcolumn = false,
		numhl = true,
		on_attach = function(bufnr)
			local gs = package.loaded.gitsigns

			local function map(mode, l, r, opts)
				opts = opts or {}
				opts.buffer = bufnr
				vim.keymap.set(mode, l, r, opts)
			end

			map("n", "]c", function()
				if vim.wo.diff then
					return "]c"
				end
				vim.schedule(function()
					gs.next_hunk()
				end)
				return "<Ignore>"
			end, { expr = true })

			map("n", "[c", function()
				if vim.wo.diff then
					return "[c"
				end
				vim.schedule(function()
					gs.prev_hunk()
				end)
				return "<Ignore>"
			end, { expr = true })

			local whichkey = require("which-key")
			local gitKeymap = {
				g = {
					name = "Git",
					b = { "<cmd>lua require('gitsigns').blame_line({ full = true })<cr>", "Blame" },
					c = {
						"<cmd>lua require('gitsigns').toggle_current_line_blame()<cr>",
						"Toggle Current Line Blame",
					},

					d = {
						"<cmd>lua require('tw.config.Git').diffSplit(vim.fn.input('[Commit] > '))<cr>",
						"Diff Split (Against Commit)",
					},

					h = { ":0Gclog!<cr>", "History" },
					k = { "Git commit<cr>", "Commit" },

					l = { ":<C-u>Git log -n 50 --graph --decorate --oneline<cr>", "Log" },

					o = {
						"<cmd>lua require('tw.config.Git').browseCurrentLine()<cr>",
						"Open Current Line in Browser",
					},
					p = { "<cmd>lua require('gitsigns').preview_hunk()<cr>", "Preview Hunk" },

					x = { "<cmd>lua require('gitsigns').reset_hunk()<cr>", "Reset Hunk" },
					X = { "<cmd>lua require('gitsigns').reset_buffer()<cr>", "Reset Buffer" },

					w = { "<cmd>Gwrite<cr>", "Git write" },
					W = { "<cmd>Gwrite!<cr>", "Git write" },

					s = { "<cmd>lua require('gitsigns').stage_hunk()<cr>", "Stage Hunk" },
					S = { "<cmd>lua require('gitsigns').stage_buffer()<cr>", "Stage Buffer" },

					u = { "<cmd>lua require('gitsigns').undo_stage_hunk()<cr>", "Undo Stage Hunk" },
					U = { "<cmd>lua require('gitsigns').reset_buffer_index()<cr>", "Reset Buffer Index" },
				},
			}

			whichkey.register(gitKeymap, {
				mode = "n",
				prefix = "<leader>",
				buffer = bufnr,
				silent = true,
				noremap = true,
				nowait = false,
			})

			local operatorPendingKeymap = {
				i = {
					h = { "<cmd>lua require('gitsigns').select_hunk()<cr>", "Select In Hunk" },
				},
			}

			whichkey.register(operatorPendingKeymap, {
				mode = "o",
				prefix = nil,
				buffer = bufnr,
				silent = true,
				noremap = true,
				nowait = false,
			})

			local visualKeymap = {
				i = {
					h = { "<cmd>lua require('gitsigns').select_hunk()<cr>", "Select In Hunk" },
				},
				g = {
					o = { ":'<,'>GBrowse<cr>", "Open in Browser" },
				},
			}

			whichkey.register(visualKeymap, {
				mode = "x",
				prefix = nil,
				buffer = bufnr,
				silent = true,
				noremap = true,
				nowait = false,
			})
		end,
	})
end

function M.setup()
	setup()
end

function M.gpp()
	vim.cmd("Git pull --rebase")
	vim.cmd("Git push")
end

function M.diffSplit(commit)
	vim.cmd("Gdiffsplit " .. commit)
end

function M.toggleGitStatus()
	local fugitiveBuf = vim.fn.bufnr("fugitive://")
	if fugitiveBuf >= 0 and vim.fn.bufwinnr(fugitiveBuf) >= 0 then
		vim.cmd("bunload " .. fugitiveBuf)
	else
		vim.cmd("Git")
	end
end

function M.browseCurrentLine()
	local linenum = vim.api.nvim_win_get_cursor(0)
	vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
