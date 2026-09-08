package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

local navigator_config
local setup_called = false
local on_filetype_called = false
local clients = {
	setup = function()
		setup_called = true
		error("E474: Invalid argument")
	end,
	on_filetype = function()
		on_filetype_called = true
		error("E474: Invalid argument")
	end,
}
local lsp_config = {}

package.loaded["navigator"] = {
	setup = function(config)
		navigator_config = config
	end,
}
package.loaded["navigator.lspclient.clients"] = clients
package.loaded["navigator.lspclient.config"] = lsp_config
package.loaded["tw.navigator"] = nil

test("disables Navigator's redundant LSP setup", function()
	local reload_lsp = function() end
	require("tw.navigator").setup(reload_lsp)

	clients.setup()
	clients.on_filetype()

	eq(false, setup_called, "original setup called")
	eq(false, on_filetype_called, "original callback called")
	eq("all", navigator_config.lsp.disable_lsp, "Navigator LSP setup")
	eq(reload_lsp, lsp_config.reload_lsp, "LSP reload override")
end)

H.finish("navigator tests")
