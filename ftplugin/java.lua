local lsp = require("tw.config.lsp")
local capabilities = require('cmp_nvim_lsp').default_capabilities()

local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
local home = vim.loop.os_getenv("HOME")
local jdtls_home = vim.api.nvim_eval("g:jdtls_home")
local jdtls_data = vim.fn.expand(home .. "/.local/share/jdtls")

local extendedClientCapabilities = require("jdtls").extendedClientCapabilities
extendedClientCapabilities.resolveAdditionalTextEditsSupport = true
extendedClientCapabilities.classFileContentSupport = true

-- See `:help vim.lsp.start_client` for an overview of the supported `config` options.
local config = {
	-- The command that starts the language server
	-- See: https://github.com/eclipse/eclipse.jdt.ls#running-from-the-command-line
	cmd = {
		-- 💀
		"java", -- or '/path/to/java11_or_newer/bin/java'
		-- depends on if `java` is in your $PATH env variable and if it points to the right version.

		"-Declipse.application=org.eclipse.jdt.ls.core.id1",
		"-Dosgi.bundles.defaultStartLevel=4",
		"-Dosgi.checkConfiguration=true",
		"-Dosgi.sharedConfiguration.area=" .. vim.fn.expand(jdtls_home .. "/config_linux"),
		"-Dosgi.sharedConfiguration.area.readOnly=true",
		"-Dosgi.configuration.cascaded=true",
		"-Declipse.product=org.eclipse.jdt.ls.core.product",
		"-Dlog.protocol=true",
		"-Dlog.level=ALL",
		"-Xms1g",
		"--add-modules=ALL-SYSTEM",
		"--add-opens",
		"java.base/java.util=ALL-UNNAMED",
		"--add-opens",
		"java.base/java.lang=ALL-UNNAMED",

		-- 💀
		"-jar",
		vim.fn.expand(jdtls_home .. "/plugins/org.eclipse.equinox.launcher_*.jar"),

		-- 💀
		"-configuration",
		jdtls_data .. "/config_linux",

		-- 💀
		-- See `data directory configuration` section in the README
		"-data",
		jdtls_data .. "/workspace/" .. project_name,
	},

	-- 💀
	-- This is the default if not provided, you can remove it. Or adjust as needed.
	-- One dedicated LSP server & client will be started per unique root_dir
	root_dir = require("jdtls.setup").find_root({
		".git",
		"mvnw",
		"gradlew",
		"build.gradle",
		"settings.gradle",
		"pom.xml",
	}),

	-- Here you can configure eclipse.jdt.ls specific settings
	-- See https://github.com/eclipse/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request
	-- for a list of options
	settings = {
		java = {},
	},

	-- Language server `initializationOptions`
	-- You need to extend the `bundles` with paths to jar files
	-- if you want to use additional eclipse.jdt.ls plugins.
	--
	-- See https://github.com/mfussenegger/nvim-jdtls#java-debug-installation
	--
	-- If you don't plan on using the debugger or other eclipse.jdt.ls plugins you can remove this
	init_options = {
		bundles = {},
		extendedClientCapabilities = extendedClientCapabilities,
	},

	on_attach = function(client, bufnr)
		require("jdtls.setup").add_commands()
		lsp.on_attach(client, bufnr)

		local function buf_set_keymap(...)
			vim.api.nvim_buf_set_keymap(bufnr, ...)
		end

		-- Mappings.
		local opts = { noremap = true, silent = true }

		buf_set_keymap("n", "oi", "<cmd>lua require('jdtls').organize_imports()<CR>", opts)
		buf_set_keymap("n", "crv", "<cmd>lua require('jdtls').extract_variable()<CR>", opts)
		buf_set_keymap("v", "crv", "<esc><cmd>lua require('jdtls').extract_variable(true)<CR>", opts)
		buf_set_keymap("n", "crc", "<cmd>lua require('jdtls').extract_constant()<CR>", opts)
		buf_set_keymap("v", "crc", "<esc><cmd>lua require('jdtls').extract_constant(true)<CR>", opts)
		buf_set_keymap("v", "crm", "<esc><cmd>lua require('jdtls').extract_method(true)<CR>", opts)
	end,

  capabilities = capabilities,
}
-- This starts a new client & server,
-- or attaches to an existing client & server depending on the `root_dir`.
require("jdtls").start_or_attach(config)
