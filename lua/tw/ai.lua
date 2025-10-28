local M = {}

local function configureSupermaven()
	local lspkind = require("lspkind")
	local supermaven = require("supermaven-nvim")
	supermaven.setup({
		disable_keymaps = true,
	})

	lspkind.init({
		symbol_map = {
			Supermaven = "",
		},
	})

	vim.api.nvim_set_hl(0, "CmpItemKindSupermaven", { fg = "#6CC644" })
end

local function configureSupermavenKeymap()
	local completion_preview = require("supermaven-nvim.completion_preview")

	local keymap = {
		{
			"<C-f>",
			completion_preview.on_accept_suggestion,
			desc = "Supermaven Accept",
			mode = "i",
			nowait = false,
			remap = false,
		},
		{
			"<C-]>",
			completion_preview.on_dispose_inlay,
			desc = "Supermaven Dismiss",
			mode = "i",
			nowait = false,
			remap = false,
		},
	}

	-- remove default <C-f> mapping so I don't scroll down the page
	-- when the supermaven completions aren't ready yet
	vim.keymap.set("i", "<C-f>", "<Nop>", { remap = true })
	local wk = require("which-key")
	wk.add(keymap)
end

local function configureCopilot()
	require("copilot").setup({
		suggestion = {
			enabled = true,
			auto_trigger = true,
			hide_during_completion = true,
			debounce = 75,
			keymap = {
				accept = "<C-f>",
				accept_word = false,
				accept_line = false,
				next = "<C-]>",
				prev = "<C-[>",
				dismiss = "<C-e>",
			},
		},
		panel = {
			enabled = false,
		},
		nes = {
			enabled = false,
		},
	})
end

function M.setup()
	-- configureSupermaven()
	-- configureSupermavenKeymap()
	configureCopilot()
end

return M
