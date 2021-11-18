local Lua = {}

function Lua.configureLsp(on_attach, capabilities)
	-- set the path to the sumneko installation; if you previously installed via the now deprecated :LspInstall, use
	local nix_profile = vim.env.HOME .. "/.nix-profile"
	local sumneko_binary = nix_profile .. "/bin/lua-language-server"
	local sumneko_main = nix_profile .. "/extras/main.lua"

	local runtime_path = vim.split(package.path, ";")
	table.insert(runtime_path, "lua/?.lua")
	table.insert(runtime_path, "lua/?/init.lua")

	return {
		on_attach = on_attach,
		capabilities = capabilities,
		cmd = { sumneko_binary, "-E", sumneko_main },
		flags = {
			debounce_text_changes = 150,
		},
		settings = {
			Lua = {
				runtime = {
					-- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
					version = "LuaJIT",
					-- Setup your lua path
					path = runtime_path,
				},
				diagnostics = {
					-- Get the language server to recognize the `vim` global
					globals = { "vim" },
				},
				workspace = {
					-- Make the server aware of Neovim runtime files
					library = vim.api.nvim_get_runtime_file("", true),
				},
				-- Do not send telemetry data containing a randomized but unique identifier
				telemetry = {
					enable = false,
				},
			},
		},
	}
end

return Lua
