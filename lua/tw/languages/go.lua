local Go = {}

function Go.configureLsp(on_attach, capabilities)
	return {
		on_attach = function(client, bufnr)
			on_attach(client, bufnr)

			-- using null_ls for formatting
			client.resolved_capabilities.document_formatting = false
			client.resolved_capabilities.document_range_formatting = false
		end,
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
