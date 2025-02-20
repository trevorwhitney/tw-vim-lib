# tw-vim-lib

A vim plugin to hold my custom functions, commands, etc. that I use in my vim configuration. I currently use this with neovim, not sure how much works with vim 8 out of the box.

# Installing

This repo should be installed as an nvim plugin. Once installed it will use packer to fetch all it's dependent plugins. Here's an example `init.vim`.

```vim
" Set to 0 for a more minimal installation without LSP support
" when set to 1, need to set these other variables as well
let s:lsp_support = 1
let s:lua_ls_path = '<PATH_TO_LUA_LANGUAGE_SERVER_ROOT_DIR>' " language server should be at /bin/lua-language-server in this directory
let s:rocks_tree_root = '<PATH_TO_LUA_ROCKS_ROOT>'
let g:jdtls_home = '<PATH_TO_JDTLS_HOME_DIR>'

let mapleader = ' ' " space as leader

lua <<EOF
-- Set the packpath so packer can install packages
local fn = vim.fn
local package_root = table.concat({fn.stdpath('data'), "site", "pack"}, "/")
vim.cmd("set packpath^=" .. package_root)

local install_path = table.concat({package_root, "packer", "start", "packer.nvim"}, "/")
local compile_path = table.concat({install_path, "plugin", "packer_compiled.lua"}, "/")

local vim_lib_install_path = package_root .. '/packer/start/tw-vim-lib'

-- all my config (including packer) is in my tw-vim-lib plugin (this repo), so fetch that manually
if fn.empty(fn.glob(vim_lib_install_path)) > 0 then
        vim_lib_bootstrap = fn.system({'git', 'clone', 'https://github.com/trevorwhitney/tw-vim-lib', vim_lib_install_path})
end

require("packer").init({
        package_root = package_root,
        compile_path = compile_path,
})

require('tw.packer').install(require('packer').use)

-- sync packer if this is a fresh install
if vim_lib_bootstrap then
  require('packer').sync()
end

local lua_ls_path = vim.api.nvim_eval('get(s:, "lua_ls_path", "")')
local rocks_tree_root = vim.api.nvim_eval('get(s:, "rocks_tree_root", "")')

require('tw').setup(lua_ls_path, rocks_tree_root)
EOF
```

## Calling Lua Functions From Vim

```lua
local M = {}

function M.test(text)
  print("Text " .. text)
end


function M.testTwo(first, second)
  print("first: " .. first)
  print("second: " .. second)
end

return M
```

```vim
command! -nargs=* Test call v:lua.require("example").test(<q-args>)
command! -nargs=* TestTwo call v:lua.require("example").testTwo(<f-args>)
```

#TODO

- telescope dap
  - https://github.com/nvim-telescope/telescope-dap.nvim
- replace vimux-go functions with native ones

## Troubleshooting

### tree-sitter

- Find the parser file being used: `echo nvim_get_runtime_file("parser/*.so", v:true)`

- minimum config for debugging:

```lua
local on_windows = vim.loop.os_uname().version:match("Windows")

local function join_paths(...)
	local path_sep = on_windows and "\\" or "/"
	local result = table.concat({ ... }, path_sep)
	return result
end

vim.cmd([[set runtimepath=$VIMRUNTIME]])

local temp_dir
if on_windows then
	temp_dir = vim.loop.os_getenv("TEMP")
else
	temp_dir = "/tmp"
end

vim.cmd("set packpath=" .. join_paths(temp_dir, "nvim", "site"))
vim.cmd("set runtimepath^=" .. join_paths(vim.loop.os_getenv("HOME"), ".local", "share", "nvim", "site", "parser"))

local package_root = join_paths(temp_dir, "nvim", "site", "pack")
local install_path = join_paths(package_root, "packer", "start", "packer.nvim")
local compile_path = join_paths(install_path, "plugin", "packer_compiled.lua")

local function load_plugins()
	local use = require("packer").use

	require("packer").init({
		package_root = package_root,
		compile_path = compile_path,
	})

  require('tw.packer').install(use)
  require("tw").setup()
end

_G.load_config = function()
	vim.lsp.set_log_level("trace")
	if vim.fn.has("nvim-0.5.1") == 1 then
		require("vim.lsp.log").set_format_func(vim.inspect)
	end
	local nvim_lsp = require("lspconfig")
	local on_attach = function(_, bufnr)
		local function buf_set_keymap(...)
			vim.api.nvim_buf_set_keymap(bufnr, ...)
		end
		local function buf_set_option(...)
			vim.api.nvim_buf_set_option(bufnr, ...)
		end

		buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

		-- Mappings.
		local opts = { noremap = true, silent = true }
		buf_set_keymap("n", "gD", "<Cmd>lua vim.lsp.buf.declaration()<CR>", opts)
		buf_set_keymap("n", "gd", "<Cmd>lua vim.lsp.buf.definition()<CR>", opts)
		buf_set_keymap("n", "K", "<Cmd>lua vim.lsp.buf.hover()<CR>", opts)
		buf_set_keymap("n", "gi", "<cmd>lua vim.lsp.buf.implementation()<CR>", opts)
		buf_set_keymap("n", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
		buf_set_keymap("n", "<space>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
		buf_set_keymap("n", "<space>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
		buf_set_keymap("n", "<space>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
		buf_set_keymap("n", "<space>D", "<cmd>lua vim.lsp.buf.type_definition()<CR>", opts)
		buf_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
		buf_set_keymap("n", "gr", "<cmd>lua vim.lsp.buf.references()<CR>", opts)
		buf_set_keymap("n", "<space>e", "<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>", opts)
		buf_set_keymap("n", "[d", "<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>", opts)
		buf_set_keymap("n", "]d", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>", opts)
		buf_set_keymap("n", "<space>q", "<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>", opts)
	end

	-- Add the server that troubles you here
	local name = "gopls"
	local cmd = { "gopls", "serve" }
	if not name then
		print("You have not defined a server name, please edit minimal_init.lua")
	end
	if not nvim_lsp[name].document_config.default_config.cmd and not cmd then
		print([[You have not defined a server default cmd for a server
      that requires it please edit minimal_init.lua]])
	end

	nvim_lsp[name].setup({
		cmd = cmd,
		on_attach = on_attach,
	})

	print(
		[[You can find your log at $HOME/.cache/nvim/lsp.log. Please paste in a github issue under a details tag as described in the issue template.]]
	)
end

if vim.fn.isdirectory(install_path) == 0 then
	vim.fn.system({ "git", "clone", "https://github.com/wbthomason/packer.nvim", install_path })
	load_plugins()
	require("packer").sync()
	vim.cmd([[autocmd User PackerComplete ++once lua load_config()]])
else
	load_plugins()
	require("packer").sync()
	_G.load_config()
end
```
