vim.fn["tw#telescope#MapKeys"]()

local trouble = require("trouble.providers.telescope")
local telescope = require("telescope")
telescope.load_extension("fzf")
telescope.load_extension("projects")

telescope.setup({
	defaults = {
		mappings = {
			i = { ["<c-b>"] = trouble.open_with_trouble },
			n = { ["<c-b>"] = trouble.open_with_trouble },
		},
	},
})
