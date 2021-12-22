vim.fn["tw#dap#MapKeys"]()



local breakpoint = {
	text = "",
	texthl = "LspDiagnosticsSignError",
	linehl = "",
	numhl = "",
}

local breakpoint_rejected = {
	text = "",
	texthl = "LspDiagnosticsSignHint",
	linehl = "",
	numhl = "",
}

local dap_stopped = {
	text = "",
	texthl = "LspDiagnosticsSignInformation",
	linehl = "DiagnosticUnderlineInfo",
	numhl = "LspDiagnosticsSignInformation",
}

require("dap")
-- set to increase log level
-- require('dap').set_log_level('TRACE')

vim.fn.sign_define("DapBreakpoint", breakpoint)
vim.fn.sign_define("DapBreakpointRejected", breakpoint_rejected)
vim.fn.sign_define("DapStopped", dap_stopped)

require("dapui").setup({
	sidebar = {
		-- You can change the order of elements in the sidebar
		elements = {
			-- Provide as ID strings or tables with "id" and "size" keys
			{
				id = "scopes",
				size = 0.75, -- Can be float or integer > 1
			},
			{ id = "breakpoints", size = 0.25 },
		},
	},
	tray = {
		size = 15,
	},
})
