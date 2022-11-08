local M = {}

local nvim_lsp = require("lspconfig")

local function mapKeys()
  -- See `:help vim.lsp.*` for documentation on any of the below functions

  local keymap = {
    g = {
      name = "Got To",
      d = { "<cmd>Telescope lsp_definitions<cr>", "Definition" },
      -- often not implemented, would rather map to definition in split
      -- D = { "<cmd>lua vim.lsp.buf.declaration()<CR>", "Declaration" },
      i = { "<cmd>Telescope lsp_implementations<cr>", "Implementation" },
      r = { "<cmd>Telescope lsp_references<cr>", "References" },
      y = { "<cmd>Telescope lsp_type_definitions<cr>", "Type Definition" },
    },
    ["]d"] = { "<cmd>lua vim.lsp.diagnostic.goto_next()<cr>", "Next Diagnostic" },
    ["[d]"] = { "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>", "Previous Diagnostic" },
    ["\\d"] = { "<cmd>lua vim.diagnostic.setloclist()<CR>", "Diagnostic List" },
  }

  local keymapWithLeader = {
    ["="] = { "<cmd>lua vim.lsp.buf.format()<cr>", "Format" },
    k = { "<cmd>lua vim.lsp.buf.hover()<cr>", "Hover" },
    K = { "<cmd>lua vim.lsp.buf.signature_help()<cr>", "Signature" },

    -- TODO: is rn more canonical?
    ["rn"] = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },
    ["re"] = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },

    -- TODO: is ca more canonical?
    a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },

    c = {
      name = "Code Action",
      a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },
      d = { "<cmd>lua vim.lsp.diagnostic.show()<cr>", "Show Diagnostics" },
      D = { "<cmd>lua vim.lsp.diagnostic.hide()<cr>", "Show Diagnostics" },
      f = { "<cmd>lua vim.diagnostic.open_float()<CR>", "Open Float" },
    },

    -- TODO: is cf better?
    e = { "<cmd>lua vim.diagnostic.open_float()<CR>", "Open Float" },

    -- TDOO: never used these, remove?
    -- buf_set_keymap("n", "<leader>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
    -- buf_set_keymap("n", "<leader>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
    -- buf_set_keymap("n", "<leader>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
  }

  local visualKeymap = {
    a = { "<cmd>lua vim.lsp.buf.code_action()<CR>", "Code Action" },
  }

  local which_key = require("which-key")

  which_key.register(keymap, {
    mode = "n",
    prefix = nil,
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

  which_key.register(keymapWithLeader, {
    mode = "n",
    prefix = "<leader>",
    buffer = nil,
    silent = true,
    noremap = true,
    nowait = false,
  })

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

  -- Override diagnostic settings for helm templates
  if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].filetype == "helm" or vim.bo[bufnr].filetype == "gotmpl" then
    vim.diagnostic.disable(bufnr)
    vim.defer_fn(function()
      vim.diagnostic.reset(nil, bufnr)
    end, 1000)
  end
end

function M.setup(sumneko_root, nix_rocks_tree)
  -- Use a loop to conveniently call 'setup' on multiple servers and
  -- map buffer local keybindings when the language server attaches
  local customLanguages = {
    sumneko_lua = require("tw.languages.lua").configureLsp(sumneko_root, nix_rocks_tree),
    gopls = require("tw.languages.go").configure_lsp,
    ccls = require("tw.languages.c").configure_lsp,
  }

  local defaultLanguages = {
    "bashls",
    "dockerls",
    "jsonls",
    "jsonnet_ls",
    "rnix",
    "terraformls",
    "tsserver",
    "vimls",
    "yamlls",
    "pyright",
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
