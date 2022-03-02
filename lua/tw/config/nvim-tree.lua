local tree_cb = require("nvim-tree.config").nvim_tree_callback
local custom_mappings = {
	{ key = "h", cb = tree_cb("close_node") },
	{ key = { "<CR>", "o", "<2-LeftMouse>", "l" }, cb = tree_cb("edit") },
}

vim.g.nvim_tree_respect_buf_cwd = 1
require("nvim-tree").setup({
	view = {
		mappings = {
			list = custom_mappings,
		},
		update_cwd = true,
		update_focused_file = {
			enable = true,
			update_cwd = true,
		},
	},
})
