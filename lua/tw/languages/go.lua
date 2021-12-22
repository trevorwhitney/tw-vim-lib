local Go = {}

function Go.configure_lsp(on_attach, capabilities)
	return {
		on_attach = on_attach,
		capabilities = capabilities,
		cmd = { "gopls", "serve" },
		flags = {
			debounce_text_changes = 150,
		},
		settings = {
			gopls = {
				analyses = {
					unusedparams = true,
				},
				buildFlags = { "-tags=e2e_gme,requires_docker" },
				staticcheck = true,
			},
		},
	}
end

function Go.debug_go_test(...)
	local dap = require("dap")
	local test_name = vim.fn["tw#go#testName"]()
	local tags = { ... }

	local args
	if tags[0] then
		args = { "--build-flags=tags", table.concat({ ... }, ","), "--", "-test.run", test_name }
	else
		args = { "-test.run", test_name }
	end

	dap.run({
		type = "go",
		name = test_name,
		request = "launch",
		mode = "test",
		program = "./${relativeFileDirname}",
		args = args,
	})
end

return Go
