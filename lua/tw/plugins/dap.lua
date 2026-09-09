return {
	{
		"mfussenegger/nvim-dap",
		cmd = { "DapContinue", "DapToggleBreakpoint" },
		keys = {
			{ "<leader>dB", desc = "List Breakpoints" },
			{ "<leader>dC", desc = "Clear Breakpoints" },
			{ "<leader>dE", desc = "Evaluate Input" },
			{ "<leader>dF", desc = "List Frames" },
			{ "<leader>dO", desc = "Toggle Console" },
			{ "<leader>dR", desc = "Run to Cursor" },
			{ "<leader>dS", desc = "Scopes" },
			{ "<leader>dT", desc = "Conditional Breakpoint" },
			{ "<leader>dU", desc = "Toggle UI" },
			{ "<leader>dX", desc = "Terminate" },
			{ "<leader>db", desc = "Step Back" },
			{ "<leader>dc", desc = "Continue" },
			{ "<leader>dd", desc = "Debug" },
			{ "<leader>de", desc = "Evaluate" },
			{ "<leader>dg", desc = "Get Session" },
			{ "<leader>dh", desc = "Hover Variables" },
			{ "<leader>di", desc = "Step Into" },
			{ "<leader>dl", desc = "Run Last" },
			{ "<leader>do", desc = "Step Over" },
			{ "<leader>dp", desc = "Pause" },
			{ "<leader>dq", desc = "Quit" },
			{ "<leader>dr", desc = "Toggle Repl" },
			{ "<leader>dt", desc = "Toggle Breakpoint" },
			{ "<leader>du", desc = "Step Out" },
			{ "<leader>dx", desc = "Disconnect" },
		},
		dependencies = {
			"nvim-telescope/telescope-dap.nvim",
			"leoluz/nvim-dap-go",
			{
				"theHamsta/nvim-dap-virtual-text",
				opts = {
					commented = true,
					virt_text_pos = "eol",
				},
			},
			{
				"rcarriga/nvim-dap-ui",
				dependencies = { "nvim-neotest/nvim-nio" },
			},
		},
		config = function()
			local tw_config = require("tw.config")
			local opts = tw_config.get()
			require("tw.dap").setup(opts.dap_configs or {})
		end,
	},
	{
		"microsoft/vscode-js-debug",
		lazy = true,
		build = "npm pkg delete optionalDependencies.microtime && npm install --legacy-peer-deps --no-save && npx gulp dapDebugServer",
	},
}
