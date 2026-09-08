local M = {}

local function ignore_navigator_lsp_setup() end

function M.setup(reload_lsp)
	require("navigator").setup({
		debug = false,
		default_mapping = false,
		lsp = {
			hover = {
				enable = false,
			},
			format_on_save = false,
			code_action = {
				enable = true,
				sign = true,
				virtual_text = false,
				sign_priority = 19,
				exclude = {
					"source.doc",
					"source.assembly",
				},
			},
			code_lens_action = {
				enable = true,
				sign = true,
				virtual_text = true,
			},
			disable_lsp = "all",
			servers = {},
		},
	})

	local navigator_clients = require("navigator.lspclient.clients")
	navigator_clients.setup = ignore_navigator_lsp_setup
	navigator_clients.on_filetype = ignore_navigator_lsp_setup
	require("navigator.lspclient.config").reload_lsp = reload_lsp
end

return M
