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

	-- Ensure tw-vim-lib modules are always findable by require().
	-- lazy.nvim disables Neovim's native package loading (vim.go.loadplugins = false)
	-- and manages the rtp itself, which can strip Nix-installed packpath entries.
	-- We add tw-vim-lib's lua directory to package.path so require("tw.*") always works,
	-- including inside lazy spec config callbacks that fire during lazy.setup().
	local tw_source = debug.getinfo(1, "S").source:sub(2) -- remove leading @
	local tw_root = vim.fn.fnamemodify(tw_source, ":h:h") -- /path/to/tw-vim-lib/lua/tw.lua -> lua -> tw-vim-lib
	local tw_lua_dir = tw_root .. "/lua"
	if not package.path:find(tw_lua_dir, 1, true) then
		package.path = tw_lua_dir .. "/?.lua;" .. tw_lua_dir .. "/?/init.lua;" .. package.path
	end

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

	-- Also add tw-vim-lib to the rtp after lazy.setup() for ftplugin/, after/, plugin/ dirs
	vim.opt.rtp:prepend(tw_root)

	require("tw.vim-options").setup()
	require("tw.augroups").setup()
	require("tw.commands").setup()
	require("tw.agent").setup()
end

return Config
