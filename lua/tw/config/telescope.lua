vim.fn["tw#telescope#MapKeys"]()

local telescope = require("telescope")
telescope.load_extension("fzf")
telescope.load_extension("projects")

telescope.setup({})


