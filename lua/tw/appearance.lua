local M = {}
local api = vim.api

local function setup_solarized()
	-- solarized
	vim.g.solarized_italic_comments = true
	vim.g.solarized_italic_keywords = true
	vim.g.solarized_italic_functions = true
	vim.g.solarized_italic_variables = false
	vim.g.solarized_contrast = true
	vim.g.solarized_borders = true
	vim.g.solarized_disable_background = true
end

local function setup_everforest()
	require("everforest").setup({
		background = "soft",
		ui_contrast = "high",
		on_highlights = function(_, _) end,
		colours_override = function(_) end,
	})
end

local function change_colors()
	if vim.fn.has("macunix") then
		local current_style = vim.fn.system("defaults read -g AppleInterfaceStyle")
		local dark_re = vim.regex("^Dark")
		local match = dark_re:match_str(current_style)

		if match then
			vim.opt.background = "dark"
			vim.system({ "change-background", "dark" })
		else
			vim.opt.background = "light"
			vim.system({ "change-background", "light" })
		end
	else
		vim.opt.background = os.getenv("BACKGROUND") or "light"
		-- TODO: call change-background on non macOS systems
	end

	vim.cmd("colorscheme everforest")
	require("lualine").setup({ options = { theme = "everforest" } })

	-- different theme options
	-- vim.cmd("colorscheme everforest")
	-- vim.cmd("colorscheme flexoki")
	-- require("solarized").set()
end

local function map_keys()
	local wk = require("which-key")
	local keymap = {
		{
			"<leader>ic",
			function()
				M.switch_colors()
			end,
			desc = "Reset Colors (to System)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>id",
			function()
				vim.opt.background = "dark"
				vim.system({ "change-background", "dark" })
				vim.cmd("colorscheme everforest")
				require("lualine").setup({ options = { theme = "everforest" } })
			end,
			desc = "Dark Mode",
			nowait = false,
			remap = false,
		},
		{
			"<leader>il",
			function()
				vim.opt.background = "light"
				vim.system({ "change-background", "light" })
				vim.cmd("colorscheme everforest")
				require("lualine").setup({ options = { theme = "everforest" } })
			end,
			desc = "Light Mode",
			nowait = false,
			remap = false,
		},
	}
	wk.add(keymap)
end

function M.setup()
	vim.opt.termguicolors = true

	setup_solarized()
	setup_everforest()

	change_colors()
	map_keys()
	api.nvim_create_autocmd("Signal", { pattern = "SIGUSR1", callback = change_colors })
end

function M.switch_colors()
	change_colors()
end

return M
