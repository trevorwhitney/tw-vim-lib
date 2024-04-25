local M = {}

local function settings()
	local set = vim.opt
	set.tabstop = 2
	set.shiftwidth = 2
end

local function keybindings()
	local goKeymap = {
		d = {
			name = "Debug",
			d = { ":w<cr> <cmd>lua require('tw.languages.go').debug()<cr>", "Debug" },
			D = {
				":w<cr> <cmd>lua require('tw.languages.go').debug(vim.fn.input('[Build Flags] > '))<cr>",
				"Debug (With Flags)",
			},
			m = {
				":w<cr> <cmd>lua require('tw.languages.go').remote_debug(vim.fn.input('[Remote Path] > '), vim.fn.input('[Port] > '))<cr>",
				"Remote Debug",
			},
		},

		-- Test
		t = {
			name = "Test",
			a = { ":w<cr> :GolangTestCurrentPackage<cr>", "Package Tests" },
		},
	}

	local whichkey = require("which-key")

	whichkey.register(goKeymap, {
		mode = "n",
		prefix = "<leader>",
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})

	local goToKeymap = {
		name = "Go To",
		g = {
			t = { ":<C-u>GoAlternate<cr>", "Alternate" },
			T = { ":<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>", "Alternate (In Vertical Split)" },
			i = { ":<C-u>GoImpl<cr>", "Implementation" },
		},
	}

	whichkey.register(goToKeymap, {
		mode = "n",
		prefix = "<leader>",
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})

	local tagsKeymap = {
		name = "Go Tags",
		t = {
			j = { ":GoAddTags json<cr>", "Add JSON Tags" },
			y = { ":GoAddTags yaml<cr>", "Add YAML Tags" },
			x = { ":GoRemoveTags<cr>", "Remove Tags" },
		},
	}

	whichkey.register(tagsKeymap, {
		mode = "n",
		prefix = "<leader>",
		buffer = nil,
		silent = true,
		noremap = true,
		nowait = false,
	})
end

function M.setup()
	settings()
	keybindings()
end

M.setup()
