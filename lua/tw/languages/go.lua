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
				buildFlags = { "-tags=e2e_gme,requires_docker" },
				staticcheck = true,
			},
		},
	}
end

return Go
