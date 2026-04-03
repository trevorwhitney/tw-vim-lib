# Packer-to-lazy.nvim Migration

## Summary

Migrate the Neovim plugin management from packer.nvim to lazy.nvim. Distribute plugin specs across feature-specific files under `lua/tw/plugins/`, add lazy-loading where appropriate, and update the Nix packaging to provision lazy.nvim instead of packer.

## Motivation

packer.nvim is unmaintained. lazy.nvim is the standard Neovim plugin manager with active development, built-in lazy-loading, and a management UI.

## Architecture

### Current Flow

1. Nix installs `packer-nvim` as a vim plugin (on the rtp)
2. `tw.lua` calls `require("packer").init()` with custom paths
3. `tw.lua` calls `require("tw.plugins").install(require("packer").use)`
4. `tw/plugins.lua` calls `packer.startup()` with imperative `use()` calls for ~60 plugins
5. `tw.lua` calls `.setup()` on each feature module

### New Flow

1. Nix installs `lazy-nvim` as a vim plugin (on the rtp)
2. `tw.lua` calls `require("lazy").setup()` with `{ import = "tw.plugins" }`
3. lazy.nvim discovers and loads all spec files from `lua/tw/plugins/*.lua`
4. Feature module setup is handled in two ways:
   - For lazy-loaded plugins: setup code moves into the plugin spec's `config` callback
   - For eager plugins: `tw.lua` calls `.setup()` after `lazy.setup()` completes

### Key Configuration

```lua
require("lazy").setup({
    spec = { import = "tw.plugins" },
    install = {
        missing = true,
        colorscheme = { "catppuccin" },
    },
    performance = {
        rtp = { reset = false },  -- preserve Nix-managed rtp
    },
})
```

`performance.rtp.reset = false` is critical: lazy.nvim resets the rtp by default, which would remove Nix-managed plugins and paths.

lazy.nvim itself is Nix-provided and must NOT appear in any plugin spec file.

### Boundary Contract

Three rules govern what lives where:

1. **Plugin-dependent setup belongs in plugin spec `config` callbacks.** Any code that calls `require("some-plugin")` must run from within a lazy spec `config` callback, not from `tw.lua` directly.
2. **Non-plugin global init stays in `tw.lua`.** Vim options, autocommands, and non-plugin commands are set up directly in `tw.lua`.
3. **Cross-plugin requirements must be declared as `dependencies`.** If a plugin spec's `config` callback requires another plugin, that plugin must be listed in `dependencies`.

### Config Options Handoff

Several feature modules need runtime options from the user's `Config.setup(user_options)` call (e.g., `lsp_support`, `lua_ls_root`, `go_build_tags`, `dap_configs`). Since lazy spec files are static modules discovered via `import`, they don't receive runtime arguments.

**Mechanism:** `tw.lua` stores user options in a shared config module before calling `lazy.setup()`. Plugin spec `config` callbacks read from this shared module.

```lua
-- tw.lua (before lazy.setup):
local tw_config = require("tw.config")
tw_config.set(options)

-- In any plugin spec config callback:
local tw_config = require("tw.config")
local opts = tw_config.get()
```

This requires creating `lua/tw/config.lua` — a simple module with `set(opts)` and `get()` functions that stores options in a module-local table. This module has no plugin dependencies and can be required safely at any time.

### Lazy-Loading vs. Eager Startup: Resolution

Several existing feature modules do eager `require()` calls at the top level or call `require("plugin")` inside their `.setup()` functions. This conflicts with lazy-loading those plugins.

**Decision:** ALL plugin-dependent setup moves into lazy spec `config` callbacks. The standalone `tw/*.lua` modules remain for code organization, but they are called from within `config`, not from `tw.lua` directly.

Modules that move into lazy spec `config` callbacks:
- `tw/telescope.lua` → telescope spec `config` (eager `require("telescope")` and `require("trouble")` at top of file)
- `tw/formatting.lua` → conform.nvim spec `config` (eager `require("conform").format` at top)
- `tw/lsp.lua` → lsp spec `config` (eager `require("telescope.builtin")` at top). **Note:** LSP setup is conditional on `tw_config.get().lsp_support`; the spec's `config` callback must check this flag and skip setup if false, matching the current `if options.lsp_support then` gate in `tw.lua:60-66`
- `tw/trouble.lua` → trouble.nvim spec `config`
- `tw/appearance.lua` / `tw/statusline.lua` → lualine spec `config` (eager `require("lualine")` in statusline)
- `tw/git.lua` → gitsigns spec `config`
- `tw/dap.lua` → dap spec `config`
- `tw/nvim-cmp.lua` → cmp spec `config`
- `tw/treesitter.lua` → treesitter spec `config`
- `tw/testing.lua` → testing spec `config`. **Note:** `tw/testing.lua:36` requires `tw.agent`, which transitively requires `plenary.path` — the testing spec must list `nvim-lua/plenary.nvim` as a dependency
- `tw/which-key.lua` → which-key spec `config`
- `tw/nvim-tree.lua` → nvim-tree spec `config`
- `tw/ai.lua` → copilot spec `config` (calls `require("copilot").setup()` in `configureCopilot()` at line 49, which is NOT guarded by pcall)
- `tw/agent.lua` → must defer `require("plenary.path")` (currently at `agent/init.lua:5` top-level). Refactor to move this require inside the functions that use it. Agent setup can remain in `tw.lua` after this refactoring, since all remaining requires are local tw modules
- `tw/telescope-git-diff.lua` → has 5 top-level `require("telescope.*")` calls at lines 1-5. These must be moved inside the functions that use them. This module is only required from `tw/git.lua:252,261` inside keymap callbacks, so after refactoring it will be safe (telescope will be loaded by user interaction time)

Modules that do NOT have plugin deps and remain in `tw.lua`:
- `tw/vim-options.lua` (no plugin deps)
- `tw/augroups.lua` (no plugin deps)
- `tw/commands.lua` (no plugin deps)

## File Changes

### Nix: `nix/packages/neovim/default.nix`

- Line 135: Replace `packer-nvim` with `lazy-nvim` (`pkgs.vimPlugins.lazy-nvim`)

### Entry Point: `lua/tw.lua`

- Remove packer bootstrap code (lines 25-34: `package_root`, `install_path`, `compile_path`, `require("packer").init()`)
- Remove line 26: `vim.cmd("set packpath^=" .. package_root)` — lazy.nvim manages its own paths, and Nix-managed paths are preserved via `rtp.reset = false`
- Remove line 40: `require("tw.plugins").install(require("packer").use)`
- Add lazy.nvim setup call with `{ import = "tw.plugins" }` and `rtp.reset = false`
- Before calling `lazy.setup()`, store user options via `require("tw.config").set(options)` (see "Config Options Handoff" section)
- Remove all `.setup()` calls for feature modules that move into lazy spec `config` callbacks (telescope, lsp, formatting, trouble, appearance, dap, cmp, treesitter, testing, which-key, nvim-tree, git, ai)
- Keep `.setup()` calls only for: `tw.vim-options`, `tw.augroups`, `tw.commands`, `tw.agent` (after agent refactoring to defer plenary require)

### New Module: `lua/tw/config.lua`

A simple shared config module that stores user options for access by lazy spec `config` callbacks:

```lua
local M = {}
local _options = {}

function M.set(opts)
    _options = opts
end

function M.get()
    return _options
end

return M
```

This module has no plugin dependencies and can be required safely at any time.

### Delete: `lua/tw/plugins.lua`

This file is replaced by the `lua/tw/plugins/` directory. The `use("wbthomason/packer.nvim")` self-reference is dropped since lazy.nvim is Nix-provided.

supermaven-nvim is commented out in the current config and is intentionally excluded from the migration.

### New Directory: `lua/tw/plugins/`

Each file returns a Lua table (list of lazy.nvim plugin specs).

### Complete Plugin Inventory

Every plugin from `lua/tw/plugins.lua` is accounted for below. Total: 62 plugins (excluding the packer self-reference).

#### `lua/tw/plugins/lsp.lua`

Plugins: nvim-lspconfig, navigator.lua (+ guihua.lua), vim-go

- nvim-lspconfig: `event = { "BufReadPre", "BufNewFile" }`, `dependencies = { "nvim-telescope/telescope.nvim" }` (tw/lsp.lua:3 requires `telescope.builtin`)
- navigator.lua: `event = { "BufReadPre", "BufNewFile" }`, `dependencies = { "ray-x/guihua.lua", "neovim/nvim-lspconfig" }`
- guihua.lua: `build = "cd lua/fzy && make"`
- vim-go: `ft = "go"`
- `config` callback reads options from `require("tw.config").get()` and checks `lsp_support` flag — skips `require("tw.lsp").setup()` if `lsp_support = false`

#### `lua/tw/plugins/telescope.lua`

Plugins: telescope.nvim, plenary.nvim, telescope-live-grep-args, telescope-fzf-native

- telescope.nvim: `cmd = "Telescope"`, `dependencies` must include all plugins whose extensions are loaded in `tw/telescope.lua:11-15`:
  - `nvim-lua/plenary.nvim`
  - `nvim-telescope/telescope-live-grep-args.nvim`
  - `nvim-telescope/telescope-fzf-native.nvim` (build = "make")
  - `ThePrimeagen/refactoring.nvim`
  - `nvim-telescope/telescope-dap.nvim`
  - `nvim-telescope/telescope-ui-select.nvim`
  - `stevearc/aerial.nvim`
- This ensures all extension plugins are loaded before `telescope.load_extension()` calls in the `config` callback
- `config` callback calls `require("tw.telescope").setup()` — this replaces the eager require at `tw/telescope.lua:1-3`

#### `lua/tw/plugins/dap.lua`

Plugins: nvim-dap, nvim-dap-go, nvim-dap-virtual-text, nvim-dap-ui, nvim-nio, telescope-dap, vscode-js-debug

- nvim-dap: `cmd = { "DapContinue", "DapToggleBreakpoint" }`, `keys` for DAP keybindings
- nvim-dap-go: `dependencies = { "mfussenegger/nvim-dap" }`
- nvim-dap-virtual-text: `dependencies = { "mfussenegger/nvim-dap" }`, `opts = { commented = true, virt_text_pos = "eol" }`
- nvim-dap-ui: `dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" }`
- vscode-js-debug: `lazy = true`, `build = "npm install --legacy-peer-deps --no-save && npx gulp dapDebugServer"`
- `config` callback reads `require("tw.config").get().dap_configs` and passes to `require("tw.dap").setup(dap_configs)`

**CRITICAL: Update `lua/tw/dap.lua:270`** — the hardcoded packer path `~/.local/share/nvim/site/pack/packer/opt/vscode-js-debug/` must be updated to use lazy.nvim's plugin path: `require("lazy.core.config").options.root .. "/vscode-js-debug/"`.

#### `lua/tw/plugins/cmp.lua`

Plugins: nvim-cmp + all sources, LuaSnip, friendly-snippets, cmp-dap, cmp-conventionalcommits

- nvim-cmp: `event = { "InsertEnter", "CmdlineEnter" }`, all cmp-* sources listed as `dependencies`
- LuaSnip: `build = "make install_jsregexp"`, `dependencies = { "rafamadriz/friendly-snippets" }`
- LuaSnip config loads lua and vscode snippet loaders: `require("luasnip.loaders.from_lua").lazy_load()` and `require("luasnip.loaders.from_vscode").lazy_load()`
- `config` callback calls `require("tw.nvim-cmp").setup()`
- Dependencies list (all 15):
  - `onsails/lspkind.nvim` (required by `tw/nvim-cmp.lua:6`)
  - `hrsh7th/cmp-nvim-lsp`
  - `hrsh7th/cmp-buffer`
  - `hrsh7th/cmp-path`
  - `hrsh7th/cmp-nvim-lua`
  - `hrsh7th/cmp-calc`
  - `hrsh7th/cmp-emoji`
  - `hrsh7th/cmp-omni`
  - `hrsh7th/cmp-cmdline`
  - `hrsh7th/cmp-nvim-lsp-signature-help`
  - `L3MON4D3/LuaSnip`
  - `saadparwaiz1/cmp_luasnip`
  - `rafamadriz/friendly-snippets`
  - `rcarriga/cmp-dap`
  - `davidsierradz/cmp-conventionalcommits`

#### `lua/tw/plugins/treesitter.lua`

Plugins: nvim-treesitter, nvim-treesitter-context, telescope-ui-select

- nvim-treesitter: `branch = "main"`, `event = { "BufReadPre", "BufNewFile" }`
- nvim-treesitter-context: listed as a separate spec with `event = { "BufReadPre", "BufNewFile" }`
- telescope-ui-select: listed as a separate spec (loaded by telescope extension)
- `config` callback calls `require("tw.treesitter").setup()`

#### `lua/tw/plugins/testing.lua`

Plugins: vim-test, vim-dispatch

- vim-test: `cmd = { "TestNearest", "TestFile", "TestSuite", "TestLast", "TestVisit" }`, `dependencies = { "tpope/vim-dispatch", "nvim-lua/plenary.nvim" }` (plenary needed because `tw/testing.lua:36` requires `tw.agent` which transitively requires `plenary.path`)
- vim-dispatch: `init = function() vim.g.dispatch_no_maps = 1 end` (changed from packer `config` to lazy `init` because this must run before plugin load)
- `config` callback calls `require("tw.testing").setup()`

#### `lua/tw/plugins/ui.lua`

Plugins: catppuccin, lualine, nvim-web-devicons, colorizer

- catppuccin: `name = "catppuccin"`, `priority = 1000`, `lazy = false`, `config` with `opts = { background = { light = "latte", dark = "mocha" } }`
- lualine: `event = "VeryLazy"`, `dependencies = { "nvim-tree/nvim-web-devicons", "folke/which-key.nvim" }` (which-key needed because `tw/appearance.lua:27` calls `require("which-key")` in `map_keys()`)
- lualine `config` callback calls `require("tw.appearance").setup()` which calls `require("tw.statusline").setup_lualine()`
- Note: catppuccin sets up the theme; `appearance.setup()` calls `vim.cmd.colorscheme("catppuccin")` again and configures lualine. This double-setup is intentional — catppuccin loads first with `priority = 1000`, then appearance configures the theme dynamically (light/dark) and sets up lualine
- nvim-web-devicons: `lazy = true` (loaded as dependency)
- colorizer: `event = "VeryLazy"`

#### `lua/tw/plugins/ai.lua`

Plugins: copilot.lua, copilot-lsp, copilot-cmp, lspkind.nvim, render-markdown.nvim, img-clip.nvim

- copilot.lua: `event = "InsertEnter"`, `dependencies = { "copilotlsp-nvim/copilot-lsp" }`, `init = function() vim.g.copilot_nes_debounce = 500 end` (changed from packer `config` to lazy `init` because this must run before plugin load), `config` callback calls `require("tw.ai").setup()` which runs `require("copilot").setup(...)`
- copilot-cmp: `dependencies = { "zbirenbaum/copilot.lua" }`, `config = function() require("copilot_cmp").setup() end`
- render-markdown.nvim: `ft = { "markdown" }`, `opts = { latex = { enabled = false } }`
- img-clip.nvim: `event = "VeryLazy"`

#### `lua/tw/plugins/editor.lua`

Plugins: surround, repeat, rsi, abolish, autopairs, matchup, which-key (+ mini.nvim), NrrwRgn, replacer, vim-qf, neorepl, vim-visual-multi, vim-textobj-user, vim-textobj-entire, vim-eunuch

- which-key: `event = "VeryLazy"`, `dependencies = { "echasnovski/mini.nvim" }`, `config` callback calls `require("tw.which-key").setup()`
- autopairs: `event = "InsertEnter"`, `config = function() require("nvim-autopairs").setup({}) end`
- matchup: `event = "VeryLazy"`
- vim-visual-multi: `branch = "master"`, `event = "VeryLazy"`
- refactoring.nvim: `dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" }`, `config = function() require("refactoring").setup({}) end`, `event = "VeryLazy"`
- surround, repeat, rsi, abolish, vim-eunuch: `event = "VeryLazy"` (simple tpope plugins)
- vim-textobj-user, vim-textobj-entire, textobj-markdown: `event = "VeryLazy"` (textobj-entire depends on textobj-user)
- NrrwRgn, replacer, vim-qf: `event = "VeryLazy"`
- neorepl: `cmd = "Repl"`

#### `lua/tw/plugins/editor-aerial.lua`

Aerial gets its own file due to its complex config with which-key dependency.

Plugins: aerial.nvim

- aerial: `event = "VeryLazy"`, `dependencies = { "folke/which-key.nvim" }`
- Preserve full inline `config` from `plugins.lua:247-276` (layout settings, on_attach with `{`/`}` keymap bindings via which-key)

#### `lua/tw/plugins/editor-spectre.lua`

Spectre gets its own file due to its inline config.

Plugins: nvim-spectre

- spectre: `cmd = { "Spectre" }`, `dependencies = { "nvim-lua/plenary.nvim" }`
- Preserve config: `opts = { live_update = true, use_trouble_qf = true }`

#### `lua/tw/plugins/formatting.lua`

Plugins: conform.nvim

- conform.nvim: `event = { "BufReadPre", "BufNewFile" }`
- `config` callback calls `require("tw.formatting").setup()` — this replaces the eager `require("conform").format` at `tw/formatting.lua:2`

#### `lua/tw/plugins/trouble.lua`

Plugins: trouble.nvim

- trouble.nvim: `event = { "BufReadPre", "BufNewFile" }`, `dependencies = { "nvim-tree/nvim-web-devicons" }`
- `config` callback calls `require("tw.trouble").setup()` — replaces eager require in `tw/trouble.lua:4`

#### `lua/tw/plugins/git.lua`

Plugins: fugitive, rhubarb, gitsigns, diffview

- fugitive: `event = "VeryLazy"`, `dependencies = { "tpope/vim-rhubarb" }`
- gitsigns: `event = { "BufReadPre", "BufNewFile" }`, `dependencies = { "nvim-lua/plenary.nvim" }`
- diffview: `cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" }`
- `config` callback calls `require("tw.git").setup()` for gitsigns spec

#### `lua/tw/plugins/navigation.lua`

Plugins: nvim-tree, tmux-navigator, vim-win

- nvim-tree: `cmd = { "NvimTreeToggle", "NvimTreeFindFile" }`, `dependencies = { "nvim-tree/nvim-web-devicons" }`
- nvim-tree `config` callback calls `require("tw.nvim-tree").setup()`
- tmux-navigator: `lazy = false`, `init = function() vim.g.tmux_navigator_no_mappings = 1 end`
- vim-win: `event = "VeryLazy"`

#### `lua/tw/plugins/filetype.lua`

Filetype-specific plugins: vim-jsonnet, vim-helm, vim-river, vim-alloy, vim-kitty, vim-yaml-folds, nvim-jdtls, vader.vim, image.nvim

- vim-jsonnet: `ft = "jsonnet"`
- vim-helm: `ft = "helm"`
- vim-river: `ft = "river"`
- vim-alloy: `ft = "alloy"`
- vim-kitty: `ft = "kitty"`
- vim-yaml-folds: `ft = "yaml"`
- nvim-jdtls: `ft = "java"`
- vader.vim: `ft = "vader"`
- image.nvim: `ft = { "markdown", "neorg" }`, `config` preserving `backend = "kitty"`, `integrations.markdown.enabled = true`, `hijack_file_patterns`

### Feature Module Changes

Each `tw/*.lua` feature module that has eager top-level `require()` of plugin modules must be refactored:
- Wrap the eager `require()` calls inside functions (not at module scope)
- The module's `.setup()` function is called from the lazy spec `config` callback, not from `tw.lua`

Example for `tw/telescope.lua`:
```lua
-- BEFORE (broken with lazy-loading):
local trouble = require("trouble")
local telescope = require("telescope")

-- AFTER:
local M = {}
function M.setup()
    local trouble = require("trouble")
    local telescope = require("telescope")
    -- ... rest of setup
end
return M
```

### Required Code Fix: `lua/tw/dap.lua:270`

Update the hardcoded packer path:
```lua
-- BEFORE:
vim.env.HOME .. "/.local/share/nvim/site/pack/packer/opt/vscode-js-debug/dist/src/dapDebugServer.js"

-- AFTER:
require("lazy.core.config").options.root .. "/vscode-js-debug/dist/src/dapDebugServer.js"
```

### Comment Cleanup: `lua/tw/which-key.lua:483`

Update the stale reference: `-- The default mappings are disabled in packer.lua` → `-- The default mappings are disabled in plugins/testing.lua`

### README: `README.md` lines 58-137

Replace the packer bootstrap snippet with a lazy.nvim equivalent. The debug bootstrap should:
1. Clone lazy.nvim if not present (standard bootstrap snippet)
2. Call `require("lazy").setup()` with the tw.plugins import
3. Include `performance.rtp.reset = false`

## Packer-to-lazy.nvim Syntax Reference

| Packer | lazy.nvim |
|---|---|
| `use("owner/repo")` | `{ "owner/repo" }` |
| `requires = {...}` | `dependencies = {...}` |
| `run = "make"` | `build = "make"` |
| `as = "name"` | `name = "name"` |
| `opt = true` | `lazy = true` |
| `wants = {...}` | (removed; use `dependencies`) |
| `config = function() end` | `config = function() end` (same) |
| `branch = "main"` | `branch = "main"` (same) |
| `packer.startup(fn)` | `require("lazy").setup(specs)` |
| `packer.init({ max_jobs = 5 })` | `install = { concurrency = 5 }` (optional; omit to use lazy.nvim default) |

Note: `max_jobs = 5` from the current packer config can be carried over as `install = { concurrency = 5 }` if parallel git operations cause issues. Otherwise, let lazy.nvim use its default.

## Lazy-Loading Strategy

| Trigger | Use Case |
|---|---|
| `event = "VeryLazy"` | General plugins needed after startup (editor utilities, git, etc.) |
| `event = "InsertEnter"` | Completion, snippets, copilot, autopairs |
| `event = { "BufReadPre", "BufNewFile" }` | LSP, treesitter, gitsigns, conform, trouble |
| `cmd = {...}` | Telescope, DAP, testing, spectre, diffview, nvim-tree |
| `ft = "..."` | Language-specific plugins (vim-go, vim-jsonnet, vim-helm, etc.) |
| `keys = {...}` | Navigation shortcuts |
| `lazy = false, priority = 1000` | Colorscheme (must load first) |

Plugins with inline `config` functions (e.g., `require("nvim-autopairs").setup({})`) need either `config = function() ... end` or `opts = {}` in their lazy spec — bare plugin entries without config will not run setup.

## Testing Plan

Baseline: the current `lua/tw/plugins.lua` declares 62 unique plugin repos (excluding the packer self-reference). Note: `:Lazy` UI may show 63 because lazy.nvim includes itself in the list.

1. **Syntax:** `make lint` passes with no new errors
2. **Nix build:** `nix build` completes without errors
3. **Startup:** `nvim --headless +qa 2>&1` produces no errors (no "module not found", no stack traces)
4. **Plugin count:** `:Lazy` UI shows all expected plugins (62 + lazy.nvim itself)
5. **Lazy-loading verification:** `:Lazy profile` confirms deferred plugins (telescope, DAP, testing, spectre, diffview, nvim-tree) are NOT loaded at startup
6. **Feature spot-checks with pass/fail criteria:**
   - LSP: `:LspInfo` shows attached language servers when editing a `.lua` or `.go` file
   - Telescope: `:Telescope find_files` opens the picker
   - Completion: typing in insert mode triggers nvim-cmp popup
   - Git: `:Git status` opens fugitive; gitsigns shows blame on file open
   - DAP: `:DapContinue` does not error (with a Go file + delve available)
   - Formatting: saving a Lua file triggers conform formatting
   - Trouble: `:Trouble diagnostics` opens the trouble window
   - Agent: `tw.agent.setup()` completes without "module not found" for plenary
7. **No eager load errors:** `require("tw.formatting")`, `require("tw.telescope")`, and `require("tw.lsp")` do NOT throw when called from lazy spec `config` callbacks
8. **Config handoff:** Verify that `require("tw.config").get()` returns the user options inside a lazy spec `config` callback (e.g., LSP config reads `lsp_support` correctly)
