local M = {}

function M.setup()
	local trouble = require("trouble")
	trouble.setup({
		-- your configuration comes here
		-- or leave it empty to use the default settings
		severity = vim.diagnostic.severity.ERROR,
	})
end

return M
