local Config = {}

local function configureNullLs()
	local null_ls = require("null-ls")
	require("null-ls").config({
		-- you must define at least one source for the plugin to work
		sources = {
			null_ls.builtins.code_actions.gitsigns,
			null_ls.builtins.diagnostics.golangci_lint,
			null_ls.builtins.diagnostics.shellcheck,
			null_ls.builtins.diagnostics.vale,
			null_ls.builtins.diagnostics.vint,
			null_ls.builtins.diagnostics.write_good,
			null_ls.builtins.diagnostics.yamllint,
			null_ls.builtins.formatting.gofmt,
			null_ls.builtins.formatting.goimports,
			null_ls.builtins.formatting.fixjson,
			null_ls.builtins.formatting.nixfmt,
			null_ls.builtins.formatting.prettier,
			null_ls.builtins.formatting.shfmt,
			null_ls.builtins.formatting.stylua,
			null_ls.builtins.formatting.terraform_fmt,
		},
	})
end

local function configureNativeLsp(sumneko_root, nix_rocks_tree)
	configureNullLs()

	local nvim_lsp = require("lspconfig")

	-- Use an on_attach function to only map the following keys
	-- after the language server attaches to the current buffer
	local on_attach = function(_, bufnr)
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

		buf_set_keymap("n", "<leader>k", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
		buf_set_keymap("n", "<leader>K", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)

		buf_set_keymap("n", "<leader>re", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
		buf_set_keymap("n", "<leader>a", "<cmd>lua vim.lsp.buf.code_action()<CR>", opts)
		buf_set_keymap("x", "<leader>a", "<cmd>lua vim.lsp.buf.range_code_action()<CR>", opts)

		buf_set_keymap("n", "<leader>e", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)
		buf_set_keymap("n", "[d", "<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>", opts)
		buf_set_keymap("n", "]d", "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>", opts)

		buf_set_keymap("n", "<leader>q", "<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>", opts)

		buf_set_keymap("n", "<leader>wa", "<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>", opts)
		buf_set_keymap("n", "<leader>wr", "<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>", opts)
		buf_set_keymap("n", "<leader>wl", "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>", opts)
	end

	local capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities())

	-- Use a loop to conveniently call 'setup' on multiple servers and
	-- map buffer local keybindings when the language server attaches
	local customLanguages = {
		sumneko_lua = require("tw.languages.lua").configureLsp(sumneko_root, nix_rocks_tree),
		gopls = require("tw.languages.go").configureLsp,
	}

	local defaultLanguages = {
		-- "bashls",
		-- "dockerls",
		"jdtls",
		"jsonls",
		"jsonnet_ls",
		"null-ls",
		"terraformls",
		-- "vimls",
		-- "yamlls",
	}

	for _, lsp in ipairs(defaultLanguages) do
		if nvim_lsp[lsp] then
			nvim_lsp[lsp].setup({
				on_attach = on_attach,
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
		nvim_lsp[lsp].setup(fn(on_attach, capabilities))
	end
end

local function configureTelescope()
	vim.fn["tw#telescope#MapKeys"]()

	local trouble = require("trouble.providers.telescope")
	local telescope = require("telescope")
	telescope.load_extension("fzf")
	telescope.load_extension("projects")

	telescope.setup({
		defaults = {
			mappings = {
				i = { ["<c-t>"] = trouble.open_with_trouble },
				n = { ["<c-t>"] = trouble.open_with_trouble },
			},
		},
	})
end

local function configureTrouble()
	vim.fn["tw#trouble#MapKeys"]()
end

local function configureCmp()
	local has_words_before = function()
		local line, col = unpack(vim.api.nvim_win_get_cursor(0))
		return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
	end

	local luasnip = require("luasnip")
	local cmp = require("cmp")
	cmp.setup({
		snippet = {
			expand = function(args)
				luasnip.lsp_expand(args.body)
			end,
		},
		mapping = {
			["<C-p>"] = cmp.mapping.select_prev_item(),
			["<C-n>"] = cmp.mapping.select_next_item(),
			["<C-d>"] = cmp.mapping.scroll_docs(-4),
			["<C-f>"] = cmp.mapping.scroll_docs(4),
			["<C-Space>"] = cmp.mapping.complete(),
			["<C-e>"] = cmp.mapping.close(),
			["<CR>"] = cmp.mapping.confirm({
				behavior = cmp.ConfirmBehavior.Replace,
				select = true,
			}),
			["<Tab>"] = cmp.mapping(function(fallback)
				if cmp.visible() then
					cmp.select_next_item()
				elseif luasnip.expand_or_jumpable() then
					luasnip.expand_or_jump()
				elseif has_words_before() then
					cmp.complete()
				else
					fallback()
				end
			end, { "i", "s" }),
			["<S-Tab>"] = cmp.mapping(function(fallback)
				if cmp.visible() then
					cmp.select_prev_item()
				elseif luasnip.jumpable(-1) then
					luasnip.jump(-1)
				else
					fallback()
				end
			end, { "i", "s" }),
		},
		sources = cmp.config.sources({
			{ name = "nvim_lsp" },
			{ name = "luasnip" },
			{ name = "buffer" },
			{ name = "path" },
		}),
	})

	luasnip.config.set_config({
		history = true,
	})

	require("luasnip/loaders/from_vscode").lazy_load()
end

function Config.setup(sumneko_root, nix_rocks_tree)
	require("tw.config.vim-options")
	require("tw.config.appearance")
	require("tw.config.which-key")
	require("tw.config.nvim-tree")

	configureNativeLsp(sumneko_root, nix_rocks_tree)
	configureTelescope()

	configureCmp()
	configureTrouble()
end

return Config
