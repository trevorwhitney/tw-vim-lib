local M = {}

local function solarized()
	-- solarized
	vim.g.solarized_italic_comments = true
	vim.g.solarized_italic_keywords = true
	vim.g.solarized_italic_functions = true
	vim.g.solarized_italic_variables = false
	vim.g.solarized_contrast = true
	vim.g.solarized_borders = true
	vim.g.solarized_disable_background = true
end

local function everforest()
	require("everforest").setup({
		background = "soft",
		ui_contrast = "high",
		on_highlights = function(hl, palette) end,
		colours_override = function(palette) end,
	})
end

function M.setup()
	-- light background
	vim.opt.background = "light"
	vim.opt.termguicolors = true

	solarized()
	everforest()
	vim.cmd("colorscheme everforest")
	-- vim.cmd("colorscheme flexoki")
	-- require("solarized").set()
end

return M
