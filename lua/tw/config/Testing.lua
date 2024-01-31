local M = {}

local function configure_neotest()
	local neotest_ns = vim.api.nvim_create_namespace("neotest")
	vim.diagnostic.config({
		virtual_text = {
			format = function(diagnostic)
				local message = diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
				return message
			end,
		},
	}, neotest_ns)

	require("neotest").setup({
		quickfix = {
			enabled = true,
		},
		log_level = vim.log.levels.DEBUG,
		adapters = {
			require("neotest-vim-test")({
				-- ignore_file_types = { "go" },
				ignore_file_types = {},
			}),

			-- currently not working in repos with both go and other languages
			-- see: https://github.com/nvim-neotest/neotest-go/issues/70
			--
			-- require("neotest-go")({
			-- 	experimental = {
			-- 		test_table = true,
			-- 	},
			-- }),
		},
	})

	require("neodev").setup({
		library = { plugins = { "neotest" }, types = true },
	})
end

local function configre_vim_test()
	vim.g["test#strategy"] = "dispatch"
	vim.g["test#go#gotest#options"] = "-v"
	vim.g["test#javascript#jest#options"] = "--no-coverage"
	-- vim.g["test#javascript#mocha#executable"] = "npm test --"
end

function M.setup()
	-- configure_neotest()
	configre_vim_test()
end

return M
