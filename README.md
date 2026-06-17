# tw-vim-lib

A vim plugin to hold my custom functions, commands, etc. that I use in my vim configuration. I currently use this with neovim, not sure how much works with vim 8 out of the box.

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

## Agent Sidebar

The agent sidebar lists all active agent sessions (opencode, claude, codex, pi)
with a live status indicator and an AI-generated summary of what each agent is
working on.

### Features

- **Status indicators** &mdash; an icon per session shows whether the agent is
  working, waiting for input, or dead.
- **Task descriptions** &mdash; a short (≤30 char) AI-generated summary of what
  each agent is doing, scraped from the terminal and summarized via the
  Anthropic Claude API (Haiku).
- **Loading state** &mdash; `⋯ loading...` while a description is being
  generated.
- **Error state** &mdash; `⚠ failed` when generation fails (network/auth). Rate
  limits (HTTP 429) are not cached, so they retry on the next refresh.

Descriptions are generated lazily on first display and cached per buffer. The
cache is cleared automatically when an agent terminal exits.

### Toggling

- `<leader>cv` &mdash; toggle the agent sidebar on its own.
- `<leader>\` &mdash; toggle the unified drawer (file tree + agent sidebar
  stacked below it).

### Configuration

Set your Anthropic API key in the environment to enable descriptions:

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

If the key is not set, the sidebar still works &mdash; status and session rows
render normally, the description column is just left blank.

Sidebar options are passed through `require("tw.agent").setup`:

```lua
require("tw.agent").setup({
  sidebar = {
    width = 45,        -- default; wide enough to fit descriptions
    position = "left", -- or "right"
    refresh_ms = 1000,
    show_dead = false,
  },
})
```

### Troubleshooting

- **Descriptions show `⚠ failed`** &mdash; confirm `ANTHROPIC_API_KEY` is set
  correctly and that `api.anthropic.com` is reachable. Transient rate limits
  (429) are not cached and retry automatically.
- **Descriptions are blank** &mdash; ensure `ANTHROPIC_API_KEY` is exported in
  the environment Neovim was launched from, then restart Neovim.

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

-- Bootstrap lazy.nvim for debugging
local lazypath = join_paths(temp_dir, "nvim", "lazy", "lazy.nvim")
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
		"https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

local function load_plugins()
	require("tw").setup()
end

_G.load_config = function()
	vim.lsp.set_log_level("trace")
	if vim.fn.has("nvim-0.5.1") == 1 then
		require("vim.lsp.log").set_format_func(vim.inspect)
	end
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
	if not cmd then
		print([[You have not defined a server default cmd for a server
      that requires it please edit minimal_init.lua]])
	end

	vim.lsp.config(name, {
		cmd = cmd,
		on_attach = on_attach,
	})

	print(
		[[You can find your log at $HOME/.cache/nvim/lsp.log. Please paste in a github issue under a details tag as described in the issue template.]]
	)
end

load_plugins()
_G.load_config()
```
