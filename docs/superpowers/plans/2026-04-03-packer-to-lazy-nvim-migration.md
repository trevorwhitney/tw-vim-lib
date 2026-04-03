# Packer-to-lazy.nvim Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace packer.nvim with lazy.nvim as the plugin manager, distributing plugin specs across feature-specific files with lazy-loading.

**Architecture:** Create a shared config module (`tw/config.lua`) for options handoff, create `lua/tw/plugins/*.lua` spec files, refactor feature modules to defer eager `require()` calls, rewrite `tw.lua` to bootstrap lazy.nvim, update Nix packaging.

**Tech Stack:** Lua (Neovim), lazy.nvim, Nix flakes

**Spec:** `docs/superpowers/specs/2026-04-03-packer-to-lazy-nvim-migration-design.md`

**Global rules:**
- Run `make lint` before each commit. Abort and fix if errors appear.
- Run `make format` before each commit to auto-format all files.
- If you see "module not found" errors at startup, look for top-level `require()` calls (outside functions) in feature modules — these are the culprits.

---

## File Structure

### New files
- `lua/tw/config.lua` — shared config module for options handoff
- `lua/tw/plugins/lsp.lua` — LSP plugin specs
- `lua/tw/plugins/telescope.lua` — telescope plugin specs
- `lua/tw/plugins/dap.lua` — DAP plugin specs
- `lua/tw/plugins/cmp.lua` — completion plugin specs
- `lua/tw/plugins/treesitter.lua` — treesitter plugin specs
- `lua/tw/plugins/testing.lua` — testing plugin specs
- `lua/tw/plugins/ui.lua` — UI/theme plugin specs
- `lua/tw/plugins/ai.lua` — AI/copilot plugin specs
- `lua/tw/plugins/editor.lua` — general editor plugin specs (includes aerial, spectre)
- `lua/tw/plugins/formatting.lua` — conform + trouble specs
- `lua/tw/plugins/git.lua` — git plugin specs
- `lua/tw/plugins/navigation.lua` — navigation plugin specs
- `lua/tw/plugins/filetype.lua` — filetype-specific plugin specs

### Modified files
- `nix/packages/neovim/default.nix` — swap `packer-nvim` for `lazy-nvim`
- `lua/tw.lua` — rewrite bootstrap, use lazy.nvim
- `lua/tw/telescope.lua` — defer eager requires
- `lua/tw/formatting.lua` — defer eager requires
- `lua/tw/lsp.lua:3` — delete redundant top-level require
- `lua/tw/telescope-git-diff.lua` — defer eager requires
- `lua/tw/agent/init.lua` — defer `require("plenary.path")`
- `lua/tw/dap.lua:270` — fix hardcoded packer path
- `lua/tw/which-key.lua:483` — fix stale comment
- `README.md` — update debug bootstrap snippet

### Deleted files
- `lua/tw/plugins.lua` — replaced by `lua/tw/plugins/` directory

---

### Task 1: Create config module and all plugin spec files

This task creates everything needed for lazy.nvim before touching the entry point. The old `tw.lua` and `plugins.lua` still work during this task.

**Files:**
- Create: `lua/tw/config.lua`
- Create: `lua/tw/plugins/` directory and all 14 spec files listed in File Structure

- [ ] **Step 1: Create `lua/tw/plugins/` directory**

```bash
mkdir -p lua/tw/plugins
```

- [ ] **Step 2: Create `lua/tw/config.lua`**

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

- [ ] **Step 3: Create `lua/tw/plugins/ui.lua`**

```lua
return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        lazy = false,
        opts = {
            background = {
                light = "latte",
                dark = "mocha",
            },
        },
    },
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
            "folke/which-key.nvim",
        },
        config = function()
            require("tw.appearance").setup()
        end,
    },
    { "nvim-tree/nvim-web-devicons", lazy = true },
    { "chrisbra/colorizer", event = "VeryLazy" },
}
```

- [ ] **Step 4: Create `lua/tw/plugins/editor.lua`**

Translate from `plugins.lua` inline plugins. Includes which-key, autopairs, matchup, visual-multi, refactoring, tpope plugins, text objects, NrrwRgn, replacer, vim-qf, neorepl, aerial, and spectre.

```lua
return {
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        dependencies = { "echasnovski/mini.nvim" },
        config = function()
            require("tw.which-key").setup()
        end,
    },
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        config = function()
            require("nvim-autopairs").setup({})
        end,
    },
    { "andymass/vim-matchup", event = "VeryLazy" },
    { "mg979/vim-visual-multi", branch = "master", event = "VeryLazy" },
    {
        "ThePrimeagen/refactoring.nvim",
        event = "VeryLazy",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        config = function()
            require("refactoring").setup({})
        end,
    },
    { "tpope/vim-surround", event = "VeryLazy" },
    { "tpope/vim-repeat", event = "VeryLazy" },
    { "tpope/vim-rsi", event = "VeryLazy" },
    { "tpope/vim-abolish", event = "VeryLazy" },
    { "tpope/vim-eunuch", event = "VeryLazy" },
    { "kana/vim-textobj-user", event = "VeryLazy" },
    {
        "kana/vim-textobj-entire",
        event = "VeryLazy",
        dependencies = { "kana/vim-textobj-user" },
    },
    {
        "coachshea/vim-textobj-markdown",
        event = "VeryLazy",
        dependencies = { "kana/vim-textobj-user" },
    },
    { "chrisbra/NrrwRgn", event = "VeryLazy" },
    { "gabrielpoca/replacer.nvim", event = "VeryLazy" },
    { "romainl/vim-qf", event = "VeryLazy" },
    { "ii14/neorepl.nvim", cmd = "Repl" },
    -- aerial (complex config with which-key dependency)
    {
        "stevearc/aerial.nvim",
        event = "VeryLazy",
        dependencies = { "folke/which-key.nvim" },
        config = function()
            local wk = require("which-key")
            require("aerial").setup({
                layout = {
                    max_with = { 50, 0.2 },
                },
                on_attach = function(_)
                    local keymap = {
                        {
                            "{",
                            "<cmd>AerialPrev<CR>",
                            desc = "Jump to previous symbol",
                            nowait = false,
                            remap = false,
                        },
                        {
                            "}",
                            "<cmd>AerialNext<CR>",
                            desc = "Jump to next symbol",
                            nowait = false,
                            remap = false,
                        },
                    }
                    wk.add(keymap)
                end,
            })
        end,
    },
    -- spectre (complex inline config)
    {
        "nvim-pack/nvim-spectre",
        cmd = { "Spectre" },
        dependencies = { "nvim-lua/plenary.nvim" },
        opts = {
            live_update = true,
            use_trouble_qf = true,
        },
    },
}
```

- [ ] **Step 5: Create `lua/tw/plugins/formatting.lua`**

Conform and trouble — both are load-bearing plugins required by feature modules.

```lua
return {
    {
        "stevearc/conform.nvim",
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            require("tw.formatting").setup()
        end,
    },
    {
        "folke/trouble.nvim",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("tw.trouble").setup()
        end,
    },
}
```

- [ ] **Step 6: Create `lua/tw/plugins/git.lua`**

```lua
return {
    {
        "tpope/vim-fugitive",
        event = "VeryLazy",
        dependencies = { "tpope/vim-rhubarb" },
    },
    { "tpope/vim-rhubarb", lazy = true },
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("tw.git").setup()
        end,
    },
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    },
}
```

- [ ] **Step 7: Create `lua/tw/plugins/navigation.lua`**

```lua
return {
    {
        "kyazdani42/nvim-tree.lua",
        cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("tw.nvim-tree").setup()
        end,
    },
    {
        "christoomey/vim-tmux-navigator",
        lazy = false,
        init = function()
            vim.g.tmux_navigator_no_mappings = 1
        end,
    },
    { "dstein64/vim-win", event = "VeryLazy" },
}
```

- [ ] **Step 8: Create `lua/tw/plugins/filetype.lua`**

```lua
return {
    { "google/vim-jsonnet", ft = "jsonnet" },
    { "towolf/vim-helm", ft = "helm" },
    { "rfratto/vim-river", ft = "river" },
    { "grafana/vim-alloy", ft = "alloy" },
    { "fladson/vim-kitty", ft = "kitty" },
    { "pedrohdz/vim-yaml-folds", ft = "yaml" },
    { "mfussenegger/nvim-jdtls", ft = "java" },
    { "junegunn/vader.vim", ft = "vader" },
    {
        "3rd/image.nvim",
        ft = { "markdown", "neorg" },
        config = function()
            require("image").setup({
                backend = "kitty",
                integrations = {
                    markdown = { enabled = true },
                },
                hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
            })
        end,
    },
}
```

- [ ] **Step 9: Create `lua/tw/plugins/lsp.lua`**

```lua
return {
    {
        "neovim/nvim-lspconfig",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = {
            "nvim-telescope/telescope.nvim",
        },
        config = function()
            local tw_config = require("tw.config")
            local opts = tw_config.get()
            if opts.lsp_support then
                require("tw.lsp").setup({
                    lua_ls_root = opts.lua_ls_root,
                    rocks_tree_root = opts.rocks_tree_root,
                    go_build_tags = opts.go_build_tags,
                })
            end
        end,
    },
    {
        "ray-x/navigator.lua",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = {
            { "ray-x/guihua.lua", build = "cd lua/fzy && make" },
            "neovim/nvim-lspconfig",
        },
    },
    { "fatih/vim-go", ft = "go" },
}
```

- [ ] **Step 10: Create `lua/tw/plugins/telescope.lua`**

All telescope extension plugins are listed as dependencies to ensure they're loaded before `telescope.load_extension()` calls.

```lua
return {
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-live-grep-args.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
            "ThePrimeagen/refactoring.nvim",
            "nvim-telescope/telescope-dap.nvim",
            "nvim-telescope/telescope-ui-select.nvim",
            "stevearc/aerial.nvim",
        },
        config = function()
            require("tw.telescope").setup()
        end,
    },
}
```

- [ ] **Step 11: Create `lua/tw/plugins/cmp.lua`**

Note: `lspkind.nvim` is listed as a cmp dependency (not in ai.lua) because `tw/nvim-cmp.lua:6` requires it.

```lua
return {
    {
        "hrsh7th/nvim-cmp",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            "onsails/lspkind.nvim",
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-nvim-lua",
            "hrsh7th/cmp-calc",
            "hrsh7th/cmp-emoji",
            "hrsh7th/cmp-omni",
            "hrsh7th/cmp-cmdline",
            "hrsh7th/cmp-nvim-lsp-signature-help",
            {
                "L3MON4D3/LuaSnip",
                build = "make install_jsregexp",
                dependencies = { "rafamadriz/friendly-snippets" },
            },
            "saadparwaiz1/cmp_luasnip",
            "rcarriga/cmp-dap",
            "davidsierradz/cmp-conventionalcommits",
        },
        config = function()
            require("luasnip.loaders.from_lua").lazy_load()
            require("luasnip.loaders.from_vscode").lazy_load()
            require("tw.nvim-cmp").setup()
        end,
    },
}
```

- [ ] **Step 12: Create `lua/tw/plugins/treesitter.lua`**

Note: `telescope-ui-select.nvim` is NOT declared here — it's already a telescope dependency in `telescope.lua`.

```lua
return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            require("tw.treesitter").setup()
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        event = { "BufReadPre", "BufNewFile" },
    },
}
```

- [ ] **Step 13: Create `lua/tw/plugins/dap.lua`**

```lua
return {
    {
        "mfussenegger/nvim-dap",
        cmd = { "DapContinue", "DapToggleBreakpoint" },
        dependencies = {
            "nvim-telescope/telescope-dap.nvim",
        },
        config = function()
            local tw_config = require("tw.config")
            local opts = tw_config.get()
            require("tw.dap").setup(opts.dap_configs or {})
        end,
    },
    {
        "leoluz/nvim-dap-go",
        dependencies = { "mfussenegger/nvim-dap" },
    },
    {
        "theHamsta/nvim-dap-virtual-text",
        dependencies = { "mfussenegger/nvim-dap" },
        config = function()
            require("nvim-dap-virtual-text").setup({
                commented = true,
                virt_text_pos = "eol",
            })
        end,
    },
    {
        "rcarriga/nvim-dap-ui",
        dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    },
    {
        "microsoft/vscode-js-debug",
        lazy = true,
        build = "npm install --legacy-peer-deps --no-save && npx gulp dapDebugServer",
    },
}
```

- [ ] **Step 14: Create `lua/tw/plugins/testing.lua`**

```lua
return {
    {
        "vim-test/vim-test",
        cmd = { "TestNearest", "TestFile", "TestSuite", "TestLast", "TestVisit" },
        dependencies = {
            "tpope/vim-dispatch",
            "nvim-lua/plenary.nvim",
        },
        config = function()
            require("tw.testing").setup()
        end,
    },
    {
        "tpope/vim-dispatch",
        lazy = true,
        init = function()
            -- Changed from packer `config` to lazy `init` because this must run before plugin load
            vim.g.dispatch_no_maps = 1
        end,
    },
}
```

- [ ] **Step 15: Create `lua/tw/plugins/ai.lua`**

Note: `lspkind.nvim` is intentionally NOT here — it moved to `cmp.lua` as a dependency. `supermaven-nvim` is commented out in the old config and intentionally excluded.

```lua
return {
    {
        "zbirenbaum/copilot.lua",
        event = "InsertEnter",
        dependencies = { "copilotlsp-nvim/copilot-lsp" },
        init = function()
            -- Changed from packer `config` to lazy `init` because this must run before plugin load
            vim.g.copilot_nes_debounce = 500
        end,
        config = function()
            require("tw.ai").setup()
        end,
    },
    {
        "zbirenbaum/copilot-cmp",
        dependencies = { "zbirenbaum/copilot.lua" },
        config = function()
            require("copilot_cmp").setup()
        end,
    },
    {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = { "markdown" },
        opts = {
            latex = {
                enabled = false,
            },
        },
    },
    { "HakonHarnes/img-clip.nvim", event = "VeryLazy" },
}
```

- [ ] **Step 16: Commit spec files**

```
git add lua/tw/config.lua lua/tw/plugins/
git commit -m "feat: add lazy.nvim plugin spec files and config module"
```

---

### Task 2: Refactor feature modules with eager requires

Refactor modules that have top-level `require()` of plugin modules so they work with lazy-loading.

**Files:**
- Modify: `lua/tw/telescope.lua`
- Modify: `lua/tw/formatting.lua`
- Modify: `lua/tw/lsp.lua`
- Modify: `lua/tw/telescope-git-diff.lua`
- Modify: `lua/tw/agent/init.lua`
- Modify: `lua/tw/dap.lua`
- Modify: `lua/tw/which-key.lua`

- [ ] **Step 1: Refactor `lua/tw/telescope.lua` — move eager requires into `configure()`**

Lines 1-3 have top-level requires of `trouble`, `telescope`, and `telescope.actions`. Move them inside `configure()`, and move `openTroubleQF` inside `configure()` too (it references `actions` and `trouble`).

```lua
-- BEFORE (lines 1-4):
local trouble = require("trouble")
local telescope = require("telescope")
local actions = require("telescope.actions")
local fn = vim.fn

-- AFTER (lines 1):
local fn = vim.fn

-- And modify configure() to:
local function configure()
    local trouble = require("trouble")
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    local function openTroubleQF(prompt_bufnr)
        actions.send_to_qflist(prompt_bufnr)
        trouble.open("quickfix")
    end

    telescope.load_extension("fzf")
    telescope.load_extension("refactoring")
    telescope.load_extension("dap")
    telescope.load_extension("ui-select")
    telescope.load_extension("aerial")

    telescope.setup({
        pickers = {
            colorscheme = {
                enable_preview = true,
            },
        },
        defaults = {
            mappings = {
                i = { ["<C-q>"] = openTroubleQF },
                n = { ["<C-q>"] = openTroubleQF },
            },
        },
    })
end
```

- [ ] **Step 2: Refactor `lua/tw/formatting.lua` — move eager require into `format()`**

```lua
-- BEFORE (line 2):
local conform_format = require("conform").format

-- AFTER: delete line 2, add require inside the format() function:
local function format(bufnr, options)
    local conform_format = require("conform").format
    -- ... rest unchanged
```

- [ ] **Step 3: Fix `lua/tw/lsp.lua:3` — delete redundant top-level require**

The local `telescope` at line 3 is redundant — `lsp.lua:65` already has a local require inside the `on_attach` callback, and all keymaps use that local. Simply delete line 3:

```lua
-- DELETE this line:
local telescope = require("telescope.builtin")
```

No other changes needed. Verify there are no other uses of the module-level `telescope` variable by searching the file.

- [ ] **Step 4: Refactor `lua/tw/telescope-git-diff.lua:1-5` — move requires into `create_picker()`**

```lua
-- BEFORE (lines 1-5):
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- AFTER: delete lines 1-5, add inside create_picker():
local function create_picker(opts)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    opts = opts or {}
    -- ... rest unchanged
```

- [ ] **Step 5: Refactor `lua/tw/agent/init.lua:5` — defer plenary require**

```lua
-- BEFORE (line 5):
local Path = require("plenary.path")

-- AFTER: delete line 5. Find every use of `Path` in the file and add
-- `local Path = require("plenary.path")` at each use site (inside the function).
```

- [ ] **Step 6: Fix hardcoded packer path in `lua/tw/dap.lua:270`**

```lua
-- BEFORE:
vim.env.HOME .. "/.local/share/nvim/site/pack/packer/opt/vscode-js-debug/dist/src/dapDebugServer.js",

-- AFTER:
require("lazy.core.config").options.root .. "/vscode-js-debug/dist/src/dapDebugServer.js",
```

Note: If this path doesn't work in the Nix environment (where `options.root` may differ), fall back to `vim.fn.stdpath("data") .. "/lazy/vscode-js-debug/dist/src/dapDebugServer.js"`.

- [ ] **Step 7: Fix stale comment in `lua/tw/which-key.lua:483`**

```lua
-- BEFORE:
-- The default mappings are disabled in packer.lua

-- AFTER:
-- The default mappings are disabled in plugins/testing.lua
```

- [ ] **Step 8: Verify no remaining packer references**

Run a grep across the codebase for any remaining `packer` references:

```bash
rg "packer" lua/ --glob '!plugins.lua' -l
```

If any files reference `packer` or `require("packer")`, fix them.

- [ ] **Step 9: Commit**

```
git add lua/tw/telescope.lua lua/tw/formatting.lua lua/tw/lsp.lua lua/tw/telescope-git-diff.lua lua/tw/agent/init.lua lua/tw/dap.lua lua/tw/which-key.lua
git commit -m "refactor: defer eager plugin requires for lazy-loading compatibility"
```

---

### Task 3: Rewrite entry point and swap Nix package

Now that spec files exist and feature modules are refactored, swap the entry point to lazy.nvim.

**Files:**
- Modify: `lua/tw.lua`
- Modify: `nix/packages/neovim/default.nix`
- Delete: `lua/tw/plugins.lua`

- [ ] **Step 1: Update Nix packaging**

In `nix/packages/neovim/default.nix`, replace `packer-nvim` with `lazy-nvim`:

```nix
-- BEFORE (line 135):
      packer-nvim
-- AFTER:
      lazy-nvim
```

- [ ] **Step 2: Rewrite `lua/tw.lua`**

Replace the entire file:

```lua
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
```

- [ ] **Step 3: Delete `lua/tw/plugins.lua`**

```bash
git rm lua/tw/plugins.lua
```

- [ ] **Step 4: Commit**

```
git add nix/packages/neovim/default.nix lua/tw.lua
git add -A
git commit -m "feat: switch entry point from packer.nvim to lazy.nvim"
```

---

### Task 4: Update README and run verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README.md debug bootstrap**

Find the packer bootstrap section in README.md (look for `local package_root` through the closing backticks after `_G.load_config()`). Replace it with:

```lua
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
```

Note: `require("tw").setup()` calls `lazy.setup()` internally — do NOT call `lazy.setup()` separately in the README snippet. That would double-initialize lazy.nvim.

- [ ] **Step 2: Run `make lint`**

Run: `make lint`
Expected: PASS with no errors.

- [ ] **Step 3: Run `make format`**

Run: `make format`
Expected: All files formatted. Commit any changes.

- [ ] **Step 4: Build Nix package**

Run: `nix build`
Expected: PASS — builds without errors. This validates the `lazy-nvim` Nix package swap.

- [ ] **Step 5: Run Go integration tests**

Run (from `test/` directory): `go test ./...`
Expected: PASS — no regressions in integration tests.

- [ ] **Step 6: Commit any remaining changes**

```
git add -A
git commit -m "chore: update README bootstrap, apply formatting"
```

---

## Post-Migration Manual Verification (Human-Only)

These checks require a running Neovim instance. Run after building with `nix build`.

1. **Startup:** `nvim --headless +qa 2>&1` produces no output (no errors)
2. **Plugin UI:** `:Lazy` shows plugin management UI with all plugins loaded
3. **Lazy profile:** `:Lazy profile` shows deferred plugins (telescope, DAP, testing, spectre, diffview, nvim-tree) NOT loaded at startup
4. **LSP:** Open a `.lua` file, run `:LspInfo` — shows attached language server
5. **Telescope:** `:Telescope find_files` opens the picker
6. **Completion:** Enter insert mode — cmp popup appears with sources
7. **Git:** `:Git status` opens fugitive; gitsigns shows blame annotations on file open
8. **DAP:** `:DapContinue` does not error (with a Go file and delve available)
9. **Formatting:** Save a Lua file — conform formatting applies
10. **Trouble:** `:Trouble diagnostics` opens the trouble window
11. **Config handoff:** In any lazy spec `config` callback, `require("tw.config").get()` returns user options (verify LSP `lsp_support` flag works)
