local M = {}

local telescope = require("telescope.builtin")

-- Track which buffers have had keymaps set to avoid duplicate registrations
local keymaps_set = {}

-- Use an on_attach function for server-specific configuration
function M.on_attach(client, bufnr)
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
	eslintrc_path = nil, -- will default to project root detection
	go_build_tags = "",
}
local options = vim.tbl_extend("force", {}, default_options)

local function setup_lsp_keymaps()
	local group = vim.api.nvim_create_augroup("LspKeymaps", {
		clear = true,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			local bufnr = args.buf
			local client = vim.lsp.get_client_by_id(args.data.client_id)

			-- Only set keymaps once per buffer, even if multiple LSP servers attach
			if keymaps_set[bufnr] then
				return
			end
			keymaps_set[bufnr] = true

			-- Cleanup tracking when buffer is deleted
			vim.api.nvim_create_autocmd("BufDelete", {
				buffer = bufnr,
				once = true,
				callback = function()
					keymaps_set[bufnr] = nil
				end,
			})

			-- Delete default LSP keybindings that we're overriding with Telescope
			pcall(vim.keymap.del, 'n', 'grr', { buffer = bufnr })
			pcall(vim.keymap.del, 'n', 'gri', { buffer = bufnr })
			pcall(vim.keymap.del, 'n', 'grt', { buffer = bufnr })
			pcall(vim.keymap.del, 'n', 'gO', { buffer = bufnr })

			-- Setup LSP keymaps with which-key
			local wk = require("which-key")
			local telescope = require("telescope.builtin")

			wk.add({
        -- Replace nvim defaults with telescope equivalents
				{ "grr", function() telescope.lsp_references({ fname_width = 0.4 }) end, buffer = bufnr, desc = "LSP: References", nowait = true },
				{ "gri", function() telescope.lsp_implementations({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Implementation" },
				{ "grt", function() telescope.lsp_type_definitions({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Type Definition" },
				{ "gO", function() telescope.lsp_document_symbols({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Document Symbols" },
				{ "gd", function() telescope.lsp_definitions({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Definition" },

        -- until I get use to the new one
				{ "gr", function() telescope.lsp_references({ fname_width = 0.4 }) end, buffer = bufnr, desc = "LSP: References", nowait = true },
				{ "gI", function() telescope.lsp_incoming_calls({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Incoming Calls" },
				{ "go", function() telescope.lsp_outgoing_calls({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Outgoing Calls" },
				{ "gD", vim.lsp.buf.declaration, buffer = bufnr, desc = "LSP: Declaration" },
				{ "gW", function() telescope.lsp_workspace_symbols({ fname_width = 0.4, reuse_win = true }) end, buffer = bufnr, desc = "LSP: Workspace Symbols" },
				{ "<M-k>", vim.lsp.buf.signature_help, buffer = bufnr, desc = "LSP: Signature Help", mode = "i" },
				{ "<leader>k", vim.lsp.buf.hover, buffer = bufnr, desc = "LSP: Hover" },
				{ "<leader>K", require("navigator.dochighlight").hi_symbol, buffer = bufnr, desc = "LSP: Highlight Symbol" },
				-- {
				-- 	"<leader>a",
				-- 	function()
				-- 		vim.lsp.buf.code_action({
				-- 			context = {
				-- 				diagnostics = vim.lsp.diagnostic.get_line_diagnostics(),
				-- 			},
				-- 		})
				-- 	end,
				-- 	buffer = bufnr,
				-- 	desc = "LSP: Code Action"
				-- },
				{
					"grn",
					function()
						local context = {}
						context.diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
						local buf = vim.api.nvim_get_current_buf()
						local startpos = vim.api.nvim_buf_get_mark(buf, "<")
						local endpos = vim.api.nvim_buf_get_mark(buf, ">")
						vim.lsp.buf.code_action({ context = context, range = { start = startpos, ["end"] = endpos } })
					end,
					buffer = bufnr,
					desc = "LSP: Range Code Action",
					mode = "v",
				},
        -- replaced by nvim default grn
				-- { "<Space>rn", vim.lsp.buf.rename, buffer = bufnr, desc = "LSP: Rename" },
				{ "<leader>la", vim.lsp.codelens.run, buffer = bufnr, desc = "LSP: Run Code Lens" },
			})
		end,
	})
end

local function setup_navigator(opts)
	require("navigator").setup({
		debug = false,
		default_mapping = false,
		lsp = {
			hover = {
				enable = false,
			},
			format_on_save = true,
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
			-- disable navigator's built-in LSP setup; we handle it via vim.lsp.config
			disable_lsp = "all",
			servers = {},
		},
	})
end

local function setup_lspconfig(opts)
	local capabilities = require("cmp_nvim_lsp").default_capabilities()

  -- servers wihtout additional customizations
	local basic_servers = {
		"dockerls",
		"eslint",
		"jsonnet_ls",
		"marksman",
		"nil_ls",
		"statix",
		"ts_ls",
		"jdtls",
		"csharp_ls",
		"helm_ls",
	}

	for _, server in ipairs(basic_servers) do
		vim.lsp.config(server, {
			on_attach = M.on_attach,
			capabilities = capabilities,
		})
		vim.lsp.enable(server)
	end

  -- servers with additional customizations
	vim.lsp.config('gopls', {
		on_attach = M.on_attach,
		capabilities = capabilities,
		settings = {
			gopls = {
				analyses = {
					unreachable = false,
					unusedparams = true,
				},
				codelenses = {
					gc_details = true,
					generate = true,
					test = true,
					tidy = true,
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
			},
		},
	})
	vim.lsp.enable('gopls')

	vim.lsp.config('lua_ls', {
		-- sumneko_root_path = opts.lua_ls_root,
		-- sumneko_binary = opts.lua_ls_root .. "/bin/lua-language-server",
		on_attach = M.on_attach,
		capabilities = capabilities,
		cmd = { opts.lua_ls_root .. "/bin/lua-language-server" },
		settings = {
			Lua = {
				-- runtime = {
				--   version = 'LuaJIT',
				--   path = vim.split(package.path, ';'),
				-- },
				diagnostics = {
					globals = { "vim" },
				},
				-- workspace = {
				--   library = vim.api.nvim_get_runtime_file("", true),
				--   checkThirdParty = false,
				-- },
				telemetry = { enable = false },
			},
		},
	})
	vim.lsp.enable('lua_ls')
end

function M.setup(lsp_options)
	vim.lsp.set_log_level(vim.log.levels.ERROR)
	lsp_options = lsp_options or {}
	options = vim.tbl_extend("force", options, lsp_options)

	setup_lsp_keymaps()
	setup_navigator(options)
	setup_lspconfig(options)
	require("tw.formatting").setup(options.use_eslint_daemon)
	local go = require("tw.languages.go")
	go.setup_build_tags(options.go_build_tags)
	go.setup_vim_go(options.go_build_tags)
end

return M
