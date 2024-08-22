local M = {}

local lspconfig = require("lspconfig")
local format = require("tw.config.Conform").format

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
function M.on_attach(_, bufnr)
  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

  -- vim.cmd("command! -nargs=0 DiagnosticShow call v:lua.vim.diagnostic.show()")
  -- vim.cmd("command! -nargs=0 DiagnosticHide call v:lua.vim.diagnostic.hide()")

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

local function setup_navigator(opts)
  require("navigator").setup({
    width = 0.75,
    height = 0.75,
    preview_height = 0.5,
    on_attach = M.on_attach,
    keymaps = {
      { key = "<leader>=", func = function()
        format({ lsp_fallback = false })
        vim.lsp.buf.format()
      end, mode = { 'n', 'v', 'x' }, desc = 'format' },
    },
    lsp = {
      lua_ls = {
        sumneko_root_path = opts.lua_ls_root,
        sumneko_binary = opts.lua_ls_root .. "/bin/lua-language-server",
      },
      gopls = function()
        return {
          on_attach = M.on_attach,
          cmd = { "gopls", "serve" },
          flags = {
            debounce_text_changes = 150,
          },
          settings = {
            gopls = {
              analyses = {
                unusedparams = true,
              },
              buildFlags = {
                "-tags=" .. opts.go_build_tags,
              },
              staticcheck = true,
            },
          },
          -- on_new_config = function(new_config, new_root_dir)
          --   local res = run_sync({ "go", "list", "-m" }, {
          --     cwd = new_root_dir,
          --   })
          --   if res.status_code ~= 0 then
          --     print("go list failed")
          --     return
          --   end

          --   new_config.settings.gopls["local"] = res.stdout
          -- end,
        }
      end,
    },
  })
end

function M.setup(lsp_options)
  vim.lsp.set_log_level("debug")

  lsp_options = lsp_options or {}
  options = vim.tbl_extend("force", options, lsp_options)

  setup_navigator(options)
  require("tw.config.Conform").setup(options.use_eslint_daemon)
  require("tw.languages.go").setupVimGo(options.go_build_tags)
end

return M
