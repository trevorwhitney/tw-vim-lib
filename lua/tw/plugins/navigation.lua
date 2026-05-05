return {
	{
		"kyazdani42/nvim-tree.lua",
		cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			require("tw.nvim-tree").setup()
		end,
	},
	{
		"christoomey/vim-tmux-navigator",
		lazy = false,
		init = function()
			vim.g.tmux_navigator_no_mappings = 1
		end,
	},
	{
		"dstein64/vim-win",
		event = "VeryLazy",
		init = function()
			vim.g.win_disable_version_warning = 1
		end,
		config = function()
			-- vim-win's defaults link WinActive -> DiffAdd (green) and
			-- WinInactive/WinNeighbor -> Todo (often red/yellow), which makes
			-- the per-window label popups appear as bright red/green blocks.
			-- Re-link them to subtler groups, and re-apply on colorscheme change.
			local function apply()
				vim.api.nvim_set_hl(0, "WinActive", { link = "PmenuSel", default = false })
				vim.api.nvim_set_hl(0, "WinInactive", { link = "Pmenu", default = false })
				vim.api.nvim_set_hl(0, "WinNeighbor", { link = "PmenuKind", default = false })
			end
			apply()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("tw_vim_win_highlights", { clear = true }),
				callback = apply,
			})
		end,
	},
}
