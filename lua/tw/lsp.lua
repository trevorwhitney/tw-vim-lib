local M = {}

local telescope = require("telescope.builtin")

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
function M.on_attach(_, bufnr)
  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

  -- Override diagnostic settings for helm templates
  if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].filetype == "helm" or vim.bo[bufnr].filetype == "gotmpl" then
    vim.diagnostic.disable(bufnr)
    vim.defer_fn(function()
      vim.diagnostic.reset(nil, bufnr)
    end, 1000)
  end
end

local default_options = {
  lua_ls_root = vim.api.nvim_eval('get(s:, "lua_ls_path", "")'),
  rocks_tree_root = vim.api.nvim_eval('get(s:, "rocks_tree_root", "")'),
  use_eslint_daemon = true,
  go_build_tags = "",
}
local options = vim.tbl_extend("force", {}, default_options)

local keymaps = {
  {
    key = "gr",
    func = function()
      telescope.lsp_references({ fname_width = 0.4 })
    end,
    desc = "async_ref",
  },
  {
    key = "gd",
    func = function()
      telescope.lsp_definitions({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "definition",
  },
  {
    key = "gi",
    func = function()
      telescope.lsp_implementations({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "implementation",
  },
  {
    key = "gI",
    func = function()
      telescope.lsp_incoming_calls({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "incoming_calls",
  },
  {
    key = "go",
    func = function()
      telescope.lsp_outgoing_calls({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "outgoing_calls",
  },
  {
    key = "gy",
    func = function()
      telescope.lsp_type_definitions({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "implementation",
  },

  { mode = "i",    key = "<M-k>",                     func = vim.lsp.buf.signature_help, desc = "signature_help" },
  { key = "<leader>k", func = vim.lsp.buf.hover,       desc = "hover" },
  { key = "<leader>K", func = require("navigator.dochighlight").hi_symbol, desc = "hi_symbol" },
  { key = "gD",        func = vim.lsp.buf.declaration,                     desc = "declaration" },
  {
    key = "<leader>g0",
    func = function()
      telescope.lsp_document_symbols({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "document_symbols",
  },
  {
    key = "gW",
    func = function()
      telescope.lsp_workspace_symbols({ fname_width = 0.4, reuse_win = true })
    end,
    desc = "workspace_symbol_live",
  },

  -- for lsp handler
  {
    key = "<leader>a",
    mode = "n",
    func = function()
      vim.lsp.buf.code_action({
        context = {
          diagnostics = vim.lsp.diagnostic.get_line_diagnostics(),
        },
      })
    end,
    desc = "code_action",
  },
  {
    key = "<leader>a",
    mode = "v",
    func = function()
      local context = {}
      context.diagnostics = vim.lsp.diagnostic.get_line_diagnostics()

      local bufnr = vim.api.nvim_get_current_buf()
      local startpos = vim.api.nvim_buf_get_mark(bufnr, "<")
      local endpos = vim.api.nvim_buf_get_mark(bufnr, ">")

      vim.lsp.buf.code_action({ context = context, range = { start = startpos, ["end"] = endpos } })
    end,
    desc = "range_code_action",
  },

  {
    key = "<Space>rn",
    func = function()
      vim.lsp.buf.rename()
    end,
    desc = "rename",
  },
  {
    key = "<leader>la",
    mode = "n",
    func = function()
      vim.lsp.codelens.run()
    end,
    desc = "run code lens action",
  },
}

local function setup_navigator(opts)
  require("navigator").setup({
    debug = false,
    on_attach = M.on_attach,
    default_mapping = false,
    keymaps = keymaps,
    lsp = {
      hover = {
        enable = false,
      },
      format_on_save = false,
      code_action = {
        enable = true,
        sign = true,
        virtual_text = false,
        sign_priority = 19,
        exclude = {
          "source.doc",
          "source.assembly",
        },
      },
      code_lens_action = {
        enable = true,
        sign = true,
        virtual_text = true,
      },
      -- additional language servers
      disable_lsp = { "ruff", "gopls", "lua_ls" }, -- defer to lspconfig for advancded configs
      servers = {
        "dockerls",
        -- "eslint",
        -- "golangci_lint_ls",
        "jsonnet_ls",
        "marksman",
        "nil_ls",
        "statix",
        "ts_ls",
        "jdtls",
        "csharp_ls",
        "helm_ls",
      }
    },
  })
end

-- directly call lspconfig setup for advanced configs
local function setup_lspconfig(opts)
  local lspconfig = require("lspconfig")
  lspconfig.gopls.setup({
    on_attach = M.on_attach,
    settings = {
      gopls = {
        analyses = {
          unreachable = false,
          unusedparams = true
        },
        codelenses = {
          gc_details = true,
          generate = true,
          test = true,
          tidy = true
        },
        buildFlags = { "-tags", opts.go_build_tags },
        completeUnimported = true,
        diagnosticsDelay = "500ms",
        gofumpt = false,
        matcher = "fuzzy",
        semanticTokens = false,
        staticcheck = true,
        symbolMatcher = "fuzzy",
        usePlaceholders = true,
      }
    },
  })

  lspconfig.lua_ls.setup({
    -- sumneko_root_path = opts.lua_ls_root,
    -- sumneko_binary = opts.lua_ls_root .. "/bin/lua-language-server",
    on_attach = M.on_attach,
    cmd = { opts.lua_ls_root .. "/bin/lua-language-server" },
    settings = {
      Lua = {
        -- runtime = {
        --   version = 'LuaJIT',
        --   path = vim.split(package.path, ';'),
        -- },
        diagnostics = {
          globals = { 'vim' },
        },
        -- workspace = {
        --   library = vim.api.nvim_get_runtime_file("", true),
        --   checkThirdParty = false,
        -- },
        telemetry = { enable = false },
      }
    }
  })
end
function M.setup(lsp_options)
  vim.lsp.set_log_level(vim.log.levels.ERROR)
  lsp_options = lsp_options or {}
  options = vim.tbl_extend("force", options, lsp_options)

  setup_navigator(options)
  setup_lspconfig(options)
  require("tw.formatting").setup(options.use_eslint_daemon)
  local go = require("tw.languages.go")
  go.setup_build_tags(options.go_build_tags)
  go.setup_vim_go(options.go_build_tags)
end

return M
