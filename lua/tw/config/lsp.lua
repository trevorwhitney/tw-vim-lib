local M = {}

local nvim_lsp = require("lspconfig")

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
function M.on_attach(_, bufnr)
	local function buf_set_keymap(...)
		vim.api.nvim_buf_set_keymap(bufnr, ...)
	end
	local function buf_set_option(...)
		vim.api.nvim_buf_set_option(bufnr, ...)
	end

	-- Enable completion triggered by <c-x><c-o>
	buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")

	-- Mappings.
	local opts = { noremap = true, silent = true }

	-- See `:help vim.lsp.*` for documentation on any of the below functions
	-- often not implemented, would rather map to definition in split
	-- buf_set_keymap('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
	buf_set_keymap("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)
	buf_set_keymap("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts)
	buf_set_keymap("n", "gr", "<cmd>Telescope lsp_references<CR>", opts)
	buf_set_keymap("n", "gy", "<cmd>Telescope lsp_type_definitions<CR>", opts)

	buf_set_keymap("n", "<leader>=", "<cmd>lua vim.lsp.buf.formatting_seq_sync()<CR>", opts)

	buf_set_keymap("n", "<leader>k", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
	buf_set_keymap("n", "<leader>K", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)

	buf_set_keymap("n", "<leader>re", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
	buf_set_keymap("n", "<leader>a", "<cmd>lua vim.lsp.buf.code_action()<CR>", opts)
	buf_set_keymap("x", "<leader>a", "<cmd>lua vim.lsp.buf.range_code_action()<CR>", opts)

	buf_set_keymap("n", "<leader>ds", "<cmd>lua vim.diagnostic.show()<CR>", opts)
	buf_set_keymap("n", "<leader>dh", "<cmd>lua vim.diagnostic.hide()<CR>", opts)

	buf_set_keymap("n", "<leader>e", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)
	buf_set_keymap("n", "[d", "<cmd>lua vim.diagnostic.goto_prev()<CR>", opts)
	buf_set_keymap("n", "]d", "<cmd>lua vim.diagnostic.goto_next()<CR>", opts)

	-- buf_set_keymap("n", "<leader>q", "<cmd>lua vim.diagnostic.set_loclist()<CR>", opts)
	buf_set_keymap("n", "\\d", "<cmd>lua vim.diagnostic.setloclist()<CR>", opts)

	buf_set_keymap("n", "<leader>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
	buf_set_keymap("n", "<leader>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
	buf_set_keymap("n", "<leader>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
end

function M.setup(sumneko_root, nix_rocks_tree)
	local capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities())

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
		"vimls",
		"yamlls",
	}

	for _, lsp in ipairs(defaultLanguages) do
		if nvim_lsp[lsp] then
			nvim_lsp[lsp].setup({
				on_attach = M.on_attach,
				capabilities = capabilities,
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
