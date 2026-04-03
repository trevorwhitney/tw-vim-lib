local Config = {}

local default_options = {
	lua_ls_root = vim.api.nvim_eval('get(s:, "lua_ls_path", "")'),
	rocks_tree_root = vim.api.nvim_eval('get(s:, "rocks_tree_root", "")'),
	lsp_support = true,
	jdtls_home = "",
	extra_path = {},
	go_build_tags = "",
	dap_configs = {},
}

local options = vim.tbl_extend("force", {}, default_options)

function Config.setup(user_options)
	user_options = user_options or {}
	options = vim.tbl_extend("force", options, user_options)

	vim.g.mapleader = " "

	local fn = vim.fn
	local path = table.concat(options.extra_path, ":") .. ":" .. fn.getenv("PATH")
	fn.setenv("PATH", path)

	if not (options.jdtls_home == nil or options.jdtls_home == "") then
		vim.g.jdtls_home = options.jdtls_home
	end

	-- Store options for lazy spec config callbacks
	require("tw.config").set(options)

	require("lazy").setup({
		spec = { import = "tw.plugins" },
		install = {
			missing = true,
			colorscheme = { "catppuccin" },
		},
		performance = {
			rtp = { reset = false }, -- preserve Nix-managed rtp
		},
	})

	require("tw.vim-options").setup()
	require("tw.augroups").setup()
	require("tw.commands").setup()
	require("tw.agent").setup()
end

return Config
