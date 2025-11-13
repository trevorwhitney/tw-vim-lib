local M = {}

local function configureGitsigns()
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

			local keymap = {
				{
					"<leader>g",
					group = "Git",
					nowait = false,
					remap = false,
				},
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
					"<leader>gd",
          function()
            local commit = vim.fn.input("[Commit] > ")
            vim.cmd("DiffviewOpen " .. commit)
          end,
					desc = "Diff Split (Against Commit)",
					nowait = false,
					remap = false,
				},
				{
          "<leader>gD",
          function()
            local commit = vim.fn.input("[Commit] > ")
            vim.cmd("DiffviewOpen " .. commit .. " -- %")
          end,
          desc = "Diff Split (Against Commit)",
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

local function configureDiffview()
	require("diffview").setup()
end

function M.setup()
	configureGitsigns()
	configureDiffview()

	-- Make :Git always open in a full-width split at the bottom
	vim.cmd([[
    cnoreabbrev <expr> Git (getcmdtype() == ':' && getcmdline() =~ '^Git$') ? 'botright Git' : 'Git'
  ]])
end
function M.gpp()
	vim.cmd("Git pull --rebase")
	vim.cmd("Git push")
end

function M.diffSplit(commit)
	vim.cmd("DiffViewOpen " .. commit)
end
function M.toggleGitStatus()
	local diffview = require("diffview")
	local diffview_lib = require("diffview.lib")

	-- Check if diffview is open
	local has_diffview = next(diffview_lib.views) ~= nil

	-- Check if fugitive buffer is open
	local fugitiveBuf = vim.fn.bufnr("fugitive://")
	local has_fugitive = fugitiveBuf >= 0 and vim.fn.bufwinnr(fugitiveBuf) >= 0

	if has_diffview then
		-- Close diffview (this will close the tab and any fugitive in it)
		vim.cmd("DiffviewClose")
	elseif has_fugitive then
		-- Close standalone fugitive buffer
		vim.cmd("bunload " .. fugitiveBuf)
	else
		-- Open combined interface
		diffview.open()
		-- diffview.emit("toggle_files")
		-- vim.cmd("Git")
	end
end

function M.browseCurrentLine()
	local linenum = vim.api.nvim_win_get_cursor(0)
	vim.cmd(unpack(linenum) .. "GBrowse")
end

return M
