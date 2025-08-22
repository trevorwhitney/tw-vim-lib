local M = {}

local function configure()
	local cmp = require("cmp")
	local luasnip = require("luasnip")
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
				cmp.select_prev_item()
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
				cmp.select_next_item()
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
					cmp.select_next_item()
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
					cmp.select_next_item()
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
		experimental = {
			-- want to reserve ghost test for supermaven
			ghost_text = false,
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
			["<C-e>"] = cmp.mapping.abort(),
			["<C-n>"] = selectNext(true),
			["<Tab>"] = selectOnlyOrNext,
			["<CR>"] = select,
			["<C-p>"] = selectPrevious(true),
			["<S-Tab>"] = selectPrevious(true),
		}),
		sources = cmp.config.sources({
			{ name = "nvim_lsp" },
			{ name = "nvim_lua" },
			{ name = "path" },
			{ name = "luasnip" },
			{ name = "treesitter" },
		}, {
			{ name = "buffer" },
		}),
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
