return {
	{
		"mfussenegger/nvim-dap",
		cmd = { "DapContinue", "DapToggleBreakpoint" },
		dependencies = { "nvim-telescope/telescope-dap.nvim" },
		config = function()
			local tw_config = require("tw.config")
			local opts = tw_config.get()
			require("tw.dap").setup({
				dap_configs = opts.dap_configs,
			})
		end,
	},
	{
		"leoluz/nvim-dap-go",
		dependencies = { "mfussenegger/nvim-dap" },
	},
	{
		"theHamsta/nvim-dap-virtual-text",
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			require("nvim-dap-virtual-text").setup({
				commented = true,
				virt_text_pos = "eol",
			})
		end,
	},
	{
		"rcarriga/nvim-dap-ui",
		dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
	},
	{
		"microsoft/vscode-js-debug",
		lazy = true,
		build = "npm install --legacy-peer-deps --no-save && npx gulp dapDebugServer",
	},
}
