local M = {}

local function configure()
	vim.g.copilot_no_tab_map = true
	vim.api.nvim_set_var("copilot_filetypes", {
		["dap-repl"] = false,
	})

	require("CopilotChat").setup({
		debug = false, -- Enable debugging
		-- See Configuration section for rest
		-- https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/canary/lua/CopilotChat/config.lua
	})
end

local function configureKeymap()
	local keymap = {
		name = "Copilot",
		["<C-j>"] = { "<Plug>(copilot-next)", "Next" },
		["<C-k>"] = { "<Plug>(copilot-previous)", "Previous" },
	}

	local which_key = require("which-key")

	which_key.register(keymap, {
		mode = "i",
		prefix = nil,
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})

	vim.keymap.set(
		"i",
		"<Plug>(vimrc:copilot-dummy-map)",
		'copilot#Accept("")',
		{ silent = true, expr = true, desc = "Copilot dummy accept, needed for nvim-cmp" }
	)
end

function M.setup()
	configure()
	configureKeymap()
end

return M
