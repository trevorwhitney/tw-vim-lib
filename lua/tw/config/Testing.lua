local M = {}

local function configure()
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

function M.setup()
	configure()
end

return M
