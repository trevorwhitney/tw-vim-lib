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

## Agent terminals

The agent integration provides local Neovim terminals for OpenCode, Claude,
Codex, and Pi: toggle panels, send selections and file context, and use `gf`
on a path in agent output to open it in an editor pane. Fullscreen agents
switch to a split when you open a file.

### Sidebar

- `<leader>cv` toggles the agent sidebar.
- `<leader>\` toggles the file tree and agent sidebar together.
- Each local terminal gets one row with its agent name, panel number, and
  process state (`running` or `dead`). `running` means the process is alive;
  it may be waiting for input.
- `j`/`k` navigate, Enter or `o` opens a panel, `a` starts a fresh session in
  the next free slot, `r` refreshes, and `q` closes the sidebar.

```text
⌬ Agents
─────────
 oc#0  running
 cl#1  running
 cx#0  running
```

```lua
require("tw.agent").setup({
  sidebar = {
    enabled = true,
    width = 45,
    refresh_ms = 1000, -- process checks only, while the sidebar is open
    show_dead = false,
  },
})
```

### Explicit continuation

Pass the agent's native resume arguments through `vrnsh`:

```sh
vrnsh claude --resume SESSION_ID
vrnsh codex resume SESSION_ID
vrnsh opencode --session SESSION_ID
```

Or continue the latest conversation:

```sh
vrnsh claude --continue
vrnsh codex resume --last
vrnsh opencode --continue
```

Inside Neovim the equivalent is `:AgentFullscreen codex resume SESSION_ID`
(or the corresponding Claude/OpenCode arguments). This command uses panel 0;
if that panel already has a live agent, it shows the existing terminal.
Continue-latest follows the CLI's session selection rules and does not restore
individual panel identities when multiple sessions share a directory.

### Simplification and compatibility

Session orchestration belongs to the external session manager. This plugin no
longer captures session IDs, restores saved sidebar entries, infers turn status,
generates AI descriptions, or publishes status/heartbeats to agentmux or Workmux.
No API key or agent hooks are needed. The old description-edit and saved-session
delete sidebar bindings (`c` and `d`) are removed.

Existing `.workmux/agent-sessions.json` and agentmux mirror files are left on disk
but are no longer read or updated here. `AGENTD_SESSION_ID` is no longer injected
into OpenCode arguments; callers should pass `--session` explicitly. The
`TW_AGENT_SLOT` environment tag is retained for external integrations.

Workmux's `.workmux/PROMPT-*.md` startup loader remains available for existing
launchers; it sends the prompt without generating tmux titles or worktree
summaries.

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
