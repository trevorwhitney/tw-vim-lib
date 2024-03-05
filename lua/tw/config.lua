local Config = {}

local default_options = {
	lua_ls_root = vim.api.nvim_eval('get(s:, "lua_ls_path", "")'),
	rocks_tree_root = vim.api.nvim_eval('get(s:, "rocks_tree_root", "")'),
	lsp_support = true,
	jdtls_home = "",
	use_eslint_daemon = true,
	extra_path = {},
	go_build_tags = "",
}

local options = vim.tbl_extend("force", {}, default_options)

function Config.setup(user_options)
	user_options = user_options or {}
	options = vim.tbl_extend("force", options, user_options)

	vim.g.mapleader = " "

	local fn = vim.fn
	-- turn off CGO for go diagnostic tools
	fn.setenv("CGO_ENABLED", 0)

	local path = table.concat(options.extra_path, ":") .. ":" .. fn.getenv("PATH")
	fn.setenv("PATH", path)

	local package_root = table.concat({ fn.stdpath("data"), "site", "pack" }, "/")
	vim.cmd("set packpath^=" .. package_root)

	local install_path = table.concat({ package_root, "packer", "start", "packer.nvim" }, "/")
	local compile_path = table.concat({ install_path, "plugin", "packer_compiled.lua" }, "/")

	require("packer").init({
		package_root = package_root,
		compile_path = compile_path,
	})

	if not (options.jdtls_home == nil or options.jdtls_home == "") then
		vim.g.jdtls_home = options.jdtls_home
	end

	-- Use CapitalCamelCase to avoid collisioins with global lua modules
	require("tw.Packer").install(require("packer").use)

	require("tw.config.VimOptions").setup()

	require("tw.config.Augroups").setup()
	require("tw.config.Commands").setup()

	require("tw.config.Appearance").setup()
	require("tw.config.Copilot").setup()
	require("tw.config.Dap").setup()
	require("tw.config.Git").setup()
	require("tw.config.NvimCmp").setup()
	require("tw.config.NvimTree").setup()
	require("tw.config.Telescope").setup()
	require("tw.config.Testing").setup()
	require("tw.config.Treesitter").setup()
	require("tw.config.Trouble").setup()
	require("tw.config.WhichKey").setup()

	if options.lsp_support then
		require("tw.config.Lsp").setup({
			lua_ls_root = options.lua_ls_root,
			rocks_tree_root = options.rocks_tree_root,
			use_eslint_daemon = options.use_eslint_daemon,
			go_build_tags = options.go_build_tags,
		})
	end
end

return Config
