local Lua = {}

function Lua.configureLsp(sumneko_root, nix_rocks_tree)
	return function(on_attach, capabilities)
		-- set the path to the sumneko installation; if you previously installed via the now deprecated :LspInstall, use
		local sumneko_binary = sumneko_root .. "/bin/lua-language-server"
		local sumneko_main = sumneko_root .. "/extras/main.lua"

		-- add vim plugin files
		local runtime_path = vim.split(package.path, ";")
		table.insert(runtime_path, "lua/?.lua")
		table.insert(runtime_path, "lua/?/init.lua")
		-- add regular lua project files
		table.insert(runtime_path, "?.lua")
		table.insert(runtime_path, "?/init.lua")
		-- add lua std library and lua rocks locations
		table.insert(runtime_path, vim.fn.expand("~/.nix-profile/share/lua/5.1/?.lua"))
		table.insert(runtime_path, vim.fn.expand("~/.nix-profile/share/lua/5.1/?/init.lua"))
		table.insert(runtime_path, vim.fn.expand("~/.luarocks/share/lua/5.1/?.lua"))
		table.insert(runtime_path, vim.fn.expand("~/.luarocks/share/lua/5.1/?/init.lua"))
		table.insert(runtime_path, vim.fn.expand(nix_rocks_tree .. "/share/lua/5.1/?.lua"))
		table.insert(runtime_path, vim.fn.expand(nix_rocks_tree .. "/share/lua/5.1/?/init.lua"))

		local library = {}

		local function addLibrary(lib)
			for _, p in pairs(vim.fn.expand(lib, false, true)) do
				p = vim.loop.fs_realpath(p)
				library[p] = true
			end
		end

		-- add runtime
		addLibrary("$VIMRUNTIME")

    -- add lua stdlib and luarocks
		addLibrary("~/.nix-profile/share/lua/5.1")
		addLibrary("~/.luarocks/share/lua/5.1")
		addLibrary(nix_rocks_tree .. "/share/lua/5.1")

    -- add runtime files (plugins, init.vim, etc.)
		local runtime_files = vim.api.nvim_get_runtime_file("", true)
		for _, p in pairs(runtime_files) do
      addLibrary(p)
		end

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
						globals = { "vim", "run_sync" },
					},
					workspace = {
						library = library,
					},
					-- Do not send telemetry data containing a randomized but unique identifier
					telemetry = {
						enable = false,
					},
				},
			},
		}
	end
end

return Lua
