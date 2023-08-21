local M = {}

local nvim_lsp = require("lspconfig")

local function mapKeys()
  local which_key = require("which-key")
  -- See `:help vim.lsp.*` for documentation on any of the below functions

  local keymap = {
    g = {
      name = "Got To",
      d = { "<cmd>lua require('telescope.builtin').lsp_definitions({fname_width=0.6})<cr>", "Definition" },
      i = {
        "<cmd>lua require('telescope.builtin').lsp_implementations({fname_width=0.6})<cr>",
        "Implementations",
      },
      r = { "<cmd>lua require('telescope.builtin').lsp_references({fname_width=0.6})<cr>", "References" },
      y = {
        "<cmd>lua require('telescope.builtin').lsp_type_definitions({fname_width=0.6})<cr>",
        "Type Definition",
      },
    },
    ["]d"] = { "<cmd>lua vim.diagnostic.goto_next()<cr>", "Next Diagnostic" },
    ["[d"] = { "<cmd>lua vim.diagnostic.goto_prev()<cr>", "Previous Diagnostic" },
  }

  which_key.register(keymap, {
    mode = "n",
    prefix = nil,
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local keymapWithLeader = {
    ["="] = { "<cmd>lua vim.lsp.buf.format()<cr>", "Format" },

    a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },

    -- TODO: can we have a function that show diagnostic if available, else show hover?
    k = { "<cmd>lua vim.lsp.buf.hover()<cr>", "Show Hover" },

    -- d is reserved for debug actions, so use uppercase D
    D = { "<cmd>lua vim.diagnostic.open_float()<CR>", "Show Diagnostic" },

    -- TODO: is rn more canonical?
    r = {
      name = "Refactor",
      n = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },
      -- ["e"] = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },
    },

    -- TDOO: never used these, remove?
    -- buf_set_keymap("n", "<leader>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
    -- buf_set_keymap("n", "<leader>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
    -- buf_set_keymap("n", "<leader>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
  }

  which_key.register(keymapWithLeader, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  local visualKeymap = {
    a = { "<cmd>lua vim.lsp.buf.code_action()<CR>", "Code Action" },
    c = {
      name = "Code",
      a = { "<cmd>lua vim.lsp.buf.code_action()<CR>", "Code Action" },
    },
  }

  which_key.register(visualKeymap, {
    mode = "x",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })
end

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
function M.on_attach(_, bufnr)
  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

  -- Mappings.
  mapKeys()

  vim.cmd("command! -nargs=0 DiagnosticShow call v:lua.vim.diagnostic.show()")
  vim.cmd("command! -nargs=0 DiagnosticHide call v:lua.vim.diagnostic.hide()")

  -- Override diagnostic settings for helm templates
  if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].filetype == "helm" or vim.bo[bufnr].filetype == "gotmpl" then
    vim.diagnostic.disable(bufnr)
    vim.defer_fn(function()
      vim.diagnostic.reset(nil, bufnr)
    end, 1000)
  end
end

function M.setup(lua_ls_root, nix_rocks_tree)
  -- Use a loop to conveniently call 'setup' on multiple servers and
  -- map buffer local keybindings when the language server attaches
  local customLanguages = {
    lua_ls = require("tw.languages.lua").configureLsp(lua_ls_root, nix_rocks_tree),
    gopls = require("tw.languages.go").configure_lsp,
    ccls = require("tw.languages.c").configure_lsp,
  }

  local defaultLanguages = {
    "bashls",
    "dockerls",
    "jsonls",
    "jsonnet_ls",
    "nixd",
    "pyright",
    "rnix",
    "terraformls",
    "tsserver",
    "vimls",
    "yamlls",
  }

  local capabilities = require("cmp_nvim_lsp").default_capabilities()

  for _, lsp in ipairs(defaultLanguages) do
    if nvim_lsp[lsp] then
      nvim_lsp[lsp].setup({
        capabilities = capabilities,
        on_attach = M.on_attach,
        flags = {
          debounce_text_changes = 150,
        },
      })
    else
      print("Failed to find language config for " .. lsp)
    end
  end

  for lsp, fn in pairs(customLanguages) do
    nvim_lsp[lsp].setup(fn(M.on_attach, capabilities))
  end
end

return M
