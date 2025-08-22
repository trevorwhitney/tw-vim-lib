local M = {}

local function options()
	vim.cmd("setlocal indentexpr=")
end

local function keybindings()
	local whichkey = require("which-key")
	local keymap = {
		{ "<leader>e", group = "Execute", nowait = false, remap = false },
		{ "<leader>eb", ":call tw#jsonnet#eval()<cr>", desc = "Evaluate Jsonnet", nowait = false, remap = false },
	}

	whichkey.add(keymap)
end

function M.ftplugin()
	options()
	keybindings()
end

M.ftplugin()
