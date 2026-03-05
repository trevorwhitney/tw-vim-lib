local M = {}
local api = vim.api

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

	vim.cmd.colorscheme("catppuccin")
	require("tw.statusline").setup_lualine()
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
	}
	wk.add(keymap)
end

function M.setup()
	vim.opt.termguicolors = true

	change_colors()
	map_keys()
	api.nvim_create_autocmd("Signal", { pattern = "SIGUSR1", callback = change_colors })
end

function M.switch_colors()
	change_colors()
end

return M
