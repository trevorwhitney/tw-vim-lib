vim.fn["tw#telescope#MapKeys"]()

local telescope = require("telescope")
telescope.load_extension("fzf")
telescope.load_extension("projects")
telescope.load_extension("refactoring")
telescope.load_extension("dap")

telescope.setup({})


