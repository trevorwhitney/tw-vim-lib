local trouble = require("trouble")
local telescope = require("telescope")
local actions = require("telescope.actions")

local function openTroubleQF(prompt_bufnr)
  actions.send_to_qflist(prompt_bufnr)
  trouble.open('quickfix')
end

local function configure()
	telescope.load_extension("fzf")
	telescope.load_extension("refactoring")
	telescope.load_extension("dap")


	telescope.setup({
		pickers = {
			colorscheme = {
				enable_preview = true,
			},
		},
		defaults = {
			mappings = {
        i = { ["<C-q>"] = openTroubleQF },
        n = { ["<C-q>"] = openTroubleQF },
			},
		},
	})
end

local M = {}

function M.setup()
	configure()
end

return M
