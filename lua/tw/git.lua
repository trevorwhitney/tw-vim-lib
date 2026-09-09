local M = {}

local function configureGitsigns()
	require("gitsigns").setup({
		current_line_blame = true,
		-- highlight numbers instead of using the sign column
		signcolumn = false,
		numhl = true,
		-- Show staged hunk signs, enables stage_hunk() to toggle (unstage) staged hunks
		signs_staged_enable = true,
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

			local keymap = {
				{
					"<leader>gS",
					"<cmd>lua require('gitsigns').stage_buffer()<cr>",
					desc = "Stage Buffer",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gU",
					"<cmd>lua require('gitsigns').reset_buffer_index()<cr>",
					desc = "Reset Buffer Index",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gW",
					"<cmd>Gwrite!<cr>",
					desc = "Git write",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gX",
					"<cmd>lua require('gitsigns').reset_buffer()<cr>",
					desc = "Reset Buffer",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gb",
					"<cmd>lua require('gitsigns').blame_line({ full = true })<cr>",
					desc = "Blame",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gc",
					"<cmd>lua require('gitsigns').toggle_current_line_blame()<cr>",
					desc = "Toggle Current Line Blame",
					nowait = false,
					remap = false,
				},
				{
					"<leader>go",
					"<cmd>lua require('tw.git').browseCurrentLine()<cr>",
					desc = "Open Current Line in Browser",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gp",
					"<cmd>lua require('gitsigns').preview_hunk()<cr>",
					desc = "Preview Hunk",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gs",
					"<cmd>lua require('gitsigns').stage_hunk()<cr>",
					desc = "Stage Hunk",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gu",
					"<cmd>lua require('gitsigns').undo_stage_hunk()<cr>",
					desc = "Undo Stage Hunk",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gw",
					"<cmd>Gwrite<cr>",
					desc = "Git write",
					nowait = false,
					remap = false,
				},
				{
					"<leader>gx",
					"<cmd>lua require('gitsigns').reset_hunk()<cr>",
					desc = "Reset Hunk",
					nowait = false,
					remap = false,
				},
				{
					"ih",
					"<cmd>lua require('gitsigns').select_hunk()<cr>",
					desc = "Select In Hunk",
					mode = "o",
					nowait = false,
					remap = false,
				},

				{
					"go",
					":'<,'>GBrowse<cr>",
					desc = "Open in Browser",
					mode = "x",
					nowait = false,
					remap = false,
				},
				{
					"ih",
					"<cmd>lua require('gitsigns').select_hunk()<cr>",
					desc = "Select In Hunk",
					mode = "x",
					nowait = false,
					remap = false,
				},
			}

			local whichkey = require("which-key")
			whichkey.add(keymap)
		end,
	})
end

local pending_jump_to_hunk = false

local function configureDiffview()
	local actions = require("diffview.actions")
	require("diffview").setup({
		hooks = {
			-- After staging/reverting a hunk, diffview refreshes and re-enters
			-- the diff buffer windows. Jump to the next change when that happens.
			diff_buf_win_enter = function(_bufnr, _winid, ctx)
				if pending_jump_to_hunk and ctx.symbol == "b" then
					pending_jump_to_hunk = false
					vim.schedule(function()
						local gs = require("gitsigns")
						pcall(gs.nav_hunk, "next", { wrap = false })
					end)
				end
			end,
		},
		keymaps = {
			view = {
				-- Stage hunk and move to next (mimics - in file panel)
				["-"] = function()
					local ok, gs = pcall(require, "gitsigns")
					if ok then
						pending_jump_to_hunk = true
						gs.stage_hunk()
					else
						vim.cmd("normal! dp")
						vim.cmd("normal! ]c")
					end
				end,
				-- Revert current hunk (mimics X in file panel)
				["X"] = function()
					local ok, gs = pcall(require, "gitsigns")
					if ok then
						pending_jump_to_hunk = true
						gs.reset_hunk()
					else
						vim.cmd("normal! do")
						vim.cmd("normal! ]c")
					end
				end,
				-- Disable diffview's default conflict keymaps that shadow agent keymaps (<leader>c*)
				-- Remap "choose ours" from co/cO to cu/cU
				{ "n", "<leader>co", false },
				{ "n", "<leader>cO", false },
				{
					"n",
					"<leader>cu",
					actions.conflict_choose("ours"),
					{ desc = "Choose the OURS version of a conflict" },
				},
				{
					"n",
					"<leader>cU",
					actions.conflict_choose_all("ours"),
					{ desc = "Choose the OURS version of a conflict for the whole file" },
				},
				-- Remap "choose base" from cb/cB to cs/cS (source/baSe)
				{ "n", "<leader>cb", false },
				{ "n", "<leader>cB", false },
				{
					"n",
					"<leader>cs",
					actions.conflict_choose("base"),
					{ desc = "Choose the BASE version of a conflict" },
				},
				{
					"n",
					"<leader>cS",
					actions.conflict_choose_all("base"),
					{ desc = "Choose the BASE version of a conflict for the whole file" },
				},
			},
		},
	})
end

function M.setup()
	configureGitsigns()
	configureDiffview()

	-- Register keymaps that don't depend on gitsigns globally so they work
	-- even on blank or non-git-tracked buffers (e.g. right after opening Vim).
	require("which-key").add({
		{
			"<leader>g",
			group = "Git",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gd",
			function()
				require("tw.telescope-git-diff").git_diff_picker()
			end,
			desc = "Diff (Commit Picker)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gD",
			function()
				require("tw.telescope-git-diff").git_diff_picker_current_file()
			end,
			desc = "Diff Current File (Commit Picker)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gf",
			function()
				vim.cmd("DiffviewFileHistory %")
			end,
			desc = "File History",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gh",
			function()
				vim.cmd("DiffviewFileHistory")
			end,
			desc = "History",
			nowait = false,
			remap = false,
		},
	})

	-- Make :Git always open in a full-width split at the bottom
	vim.cmd([[
    cnoreabbrev <expr> Git (getcmdtype() == ':' && getcmdline() =~ '^Git$') ? 'botright Git' : 'Git'
  ]])
end

function M.gpp()
	vim.cmd("Git pull --rebase")
	vim.cmd("Git push")
end

function M.toggleGitStatus()
	local diffview = require("diffview")
	local diffview_lib = require("diffview.lib")

	local view = diffview_lib.get_current_view()
	local has_diffview = next(diffview_lib.views) ~= nil

	if has_diffview then
		if view then
			-- Diffview is open AND we're on the diffview tab → close
			vim.cmd("DiffviewClose")
		else
			-- Diffview is open but we're on a different tab → focus it
			local dv = diffview_lib.views[1]
			if dv and dv.tabpage and vim.api.nvim_tabpage_is_valid(dv.tabpage) then
				vim.api.nvim_set_current_tabpage(dv.tabpage)
			else
				-- Stale view; close and reopen
				pcall(vim.cmd, "DiffviewClose")
				diffview.open()
			end
		end
	else
		-- Check for fugitive
		local fugitive_buf = vim.fn.bufnr("fugitive://")
		local has_fugitive = fugitive_buf >= 0 and vim.fn.bufwinnr(fugitive_buf) >= 0

		if has_fugitive then
			vim.cmd("bunload " .. fugitive_buf)
		else
			diffview.open()
			-- diffview.emit("toggle_files")
			-- vim.cmd("Git")
		end
	end
end

function M.browseCurrentLine()
	local linenum = vim.api.nvim_win_get_cursor(0)
	vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
