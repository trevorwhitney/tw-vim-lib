return {
	left = {
		{ ft = "NvimTree", title = "Files", size = { width = 40 } },
		{ ft = "tw-agent-sidebar", title = "Agents", size = { height = 23 } },
	},
	right = {
		{ ft = "AgentConsole", title = "Agent", size = { width = 0.4 } },
	},
	keys = {
		["<c-q>"] = false,
		["<leader>q"] = function(win)
			win:hide()
		end,
		[">"] = function(win)
			win:resize("width", 2)
		end,
		["<lt>"] = function(win)
			win:resize("width", -2)
		end,
	},
}
