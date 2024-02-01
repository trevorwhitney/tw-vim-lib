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

function M.setup()
	-- light background
	vim.opt.background = "light"
	vim.opt.termguicolors = true

	solarized()

	vim.cmd("colorscheme tw-light")
	-- require("solarized").set()
end

return M
