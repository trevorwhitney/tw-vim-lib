local M = {}

local function configure()
	local cmp = require("cmp")
	local luasnip = require("luasnip")
	local lspkind = require("lspkind")
	local select = cmp.mapping({
		i = function(fallback)
			if cmp.visible() then
				if luasnip.expandable() then
					luasnip.expand()
				else
					if cmp.get_selected_entry() then
						cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
					else
						fallback()
					end
				end
			else
				fallback()
			end
		end,
		s = cmp.mapping.confirm({ select = true }),
		c = function(fallback)
			if cmp.visible() then
				if cmp.get_active_entry() then
					cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
				else
					fallback()
				end
			else
				fallback()
			end
		end,
	})
	local function selectPrevious(snips)
		return cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
			elseif snips and luasnip.locally_jumpable(-1) then
				luasnip.jump(-1)
			else
				fallback()
			end
		end, { "i", "s" })
	end
	local function selectNext(snips)
		return cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
			elseif snips and luasnip.locally_jumpable(1) then
				luasnip.jump(1)
			else
				fallback()
			end
		end, { "i", "s" })
	end
	-- selectOnlyOrNext will select the only entry if there is only one entry, otherwise it will select the next entry
	local selectOnlyOrNext = cmp.mapping({
		i = function(fallback)
			if cmp.visible() then
				if #cmp.get_entries() == 1 then
					cmp.confirm({ select = true })
				else
					cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
				end
			elseif luasnip.locally_jumpable(1) then
				luasnip.jump(1)
			else
				fallback()
			end
		end,
		c = function(_)
			if cmp.visible() then
				if #cmp.get_entries() == 1 then
					cmp.confirm({ select = true })
				else
					cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
				end
			else
				cmp.complete()
				if #cmp.get_entries() == 1 then
					cmp.confirm({ select = true })
				end
			end
		end,
	})
	cmp.setup({
		enabled = function()
			return vim.bo[0].buftype ~= "prompt" or require("cmp_dap").is_dap_buffer()
		end,
		preselect = cmp.PreselectMode.None,
		completion = {
			autocomplete = { cmp.TriggerEvent.TextChanged },
		},
		experimental = {
			ghost_text = true,
		},
		snippet = {
			expand = function(args)
				require("luasnip").lsp_expand(args.body)
			end,
		},
		window = {
			completion = cmp.config.window.bordered(),
			documentation = cmp.config.window.bordered(),
		},
		mapping = cmp.mapping.preset.insert({
			["<C-Space>"] = cmp.mapping.complete(),
			["<C-e>"] = cmp.mapping.abort(),
			["<C-n>"] = selectNext(true),
			["<C-f>"] = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true }, { "i" }),
			["<Tab>"] = selectOnlyOrNext,
			["<CR>"] = select,
			["<C-p>"] = selectPrevious(true),
			["<S-Tab>"] = selectPrevious(true),
		}),
		sources = cmp.config.sources({
			{ name = "nvim_lsp", priority = 1000, group_index = 1 },
			{ name = "copilot", priority = 900, group_index = 1 },
			{ name = "nvim_lsp_signature_help", priority = 800, group_index = 1 },

			{ name = "luasnip", group_index = 2 },
			{ name = "nvim_lua", group_index = 2 },
			{ name = "path", group_index = 2 },
			{ name = "treesitter", group_index = 2 },
			{ name = "conventionalcommits", group_index = 2 },
			{ name = "dap", group_index = 2 },
			{ name = "buffer", grop_index = 2 },
		}),
		formatting = {
			format = lspkind.cmp_format({
				mode = "symbol_text",
				menu = {
					buffer = "[Buf]",
					nvim_lsp = "[LSP]",
					nvim_lua = "[Lua]",
					path = "[Path]",
					luasnip = "[LuaSnip]",
					treesitter = "[TS]",
					copilot = "[Copilot]",
				},
				sympbol_map = { Copilot = "" },
			}),
		},
	})

	cmp.setup.cmdline({ "/", "?" }, {
		mapping = cmp.mapping.preset.cmdline(),
		sources = {
			{ name = "buffer" },
		},
	})

	cmp.setup.cmdline(":", {
		mapping = cmp.mapping.preset.cmdline(),
		sources = cmp.config.sources({
			{ name = "path" },
		}, {
			{ name = "cmdline" },
		}),
	})
end

function M.setup()
	configure()
end

return M
