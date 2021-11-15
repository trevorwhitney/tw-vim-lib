local Go = {}

function Go.configureLsp(on_attach, capabilities)
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
				staticcheck = true,
			},
		},
	}
end

return Go
