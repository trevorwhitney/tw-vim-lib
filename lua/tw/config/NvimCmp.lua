local M = {}

---when inside a snippet, seeks to the nearest luasnip field if possible, and checks if it is jumpable
---@param dir number 1 for forward, -1 for backward; defaults to 1
---@return boolean true if a jumpable luasnip field is found while inside a snippet
local function jumpable(dir)
	local luasnip_ok, luasnip = pcall(require, "luasnip")
	if not luasnip_ok then
		return false
	end

	local win_get_cursor = vim.api.nvim_win_get_cursor
	local get_current_buf = vim.api.nvim_get_current_buf

	---sets the current buffer's luasnip to the one nearest the cursor
	---@return boolean true if a node is found, false otherwise
	local function seek_luasnip_cursor_node()
		-- for outdated versions of luasnip
		if not luasnip.session.current_nodes then
			return false
		end

		local node = luasnip.session.current_nodes[get_current_buf()]
		if not node then
			return false
		end

		local snippet = node.parent.snippet
		local exit_node = snippet.insert_nodes[0]

		local pos = win_get_cursor(0)
		pos[1] = pos[1] - 1

		-- exit early if we're past the exit node
		if exit_node then
			local exit_pos_end = exit_node.mark:pos_end()
			if (pos[1] > exit_pos_end[1]) or (pos[1] == exit_pos_end[1] and pos[2] > exit_pos_end[2]) then
				snippet:remove_from_jumplist()
				luasnip.session.current_nodes[get_current_buf()] = nil

				return false
			end
		end

		node = snippet.inner_first:jump_into(1, true)
		while node ~= nil and node.next ~= nil and node ~= snippet do
			local n_next = node.next
			local next_pos = n_next and n_next.mark:pos_begin()
			local candidate = n_next ~= snippet and next_pos and (pos[1] < next_pos[1])
				or (pos[1] == next_pos[1] and pos[2] < next_pos[2])

			-- Past unmarked exit node, exit early
			if n_next == nil or n_next == snippet.next then
				snippet:remove_from_jumplist()
				luasnip.session.current_nodes[get_current_buf()] = nil

				return false
			end

			if candidate then
				luasnip.session.current_nodes[get_current_buf()] = node
				return true
			end

			local ok
			ok, node = pcall(node.jump_from, node, 1, true) -- no_move until last stop
			if not ok then
				snippet:remove_from_jumplist()
				luasnip.session.current_nodes[get_current_buf()] = nil

				return false
			end
		end

		-- No candidate, but have an exit node
		if exit_node then
			-- to jump to the exit node, seek to snippet
			luasnip.session.current_nodes[get_current_buf()] = snippet
			return true
		end

		-- No exit node, exit from snippet
		snippet:remove_from_jumplist()
		luasnip.session.current_nodes[get_current_buf()] = nil
		return false
	end

	if dir == -1 then
		return luasnip.in_snippet() and luasnip.jumpable(-1)
	else
		return luasnip.in_snippet() and seek_luasnip_cursor_node() and luasnip.jumpable(1)
	end
end

local has_words_before = function()
	unpack = unpack or table.unpack
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local function configure()
	local cmp = require("cmp")
	local luasnip = require("luasnip")

	local select = cmp.mapping({
		i = function(fallback)
			if cmp.visible() then
				local confirm_opts = { behavior = cmp.ConfirmBehavior.Replace, select = true }
				cmp.confirm(confirm_opts)
			elseif jumpable(1) then
				luasnip.jump(1)
			else
				fallback()
			end
		end,
		s = cmp.mapping.confirm({ select = true }),
		c = cmp.mapping.confirm({ select = true }),
	})

	local selectPrevious = cmp.mapping(function(fallback)
		if cmp.visible() then
			cmp.select_prev_item()
		else
			fallback()
		end
	end, { "i", "s" })

	local selectNext = cmp.mapping(function(fallback)
		if cmp.visible() then
			cmp.select_next_item()
		else
			fallback()
		end
	end, { "i", "s" })

	cmp.setup({
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
			["<C-b>"] = cmp.mapping.scroll_docs(-4),
			["<C-B>"] = cmp.mapping.scroll_docs(4),
			["<C-e>"] = cmp.mapping.abort(),
			["<C-Space>"] = cmp.mapping.complete(),
			["<C-p>"] = selectPrevious,
			["<C-n>"] = selectNext,

			-- ["<S-Tab>"] = selectPrevious,

			["<Tab>"] = select,
			-- Uncomment to make enter accept the current selection or jumps to the next snippet field
			-- ["<CR>"] = select,
			--
			-- Uncomment to have tab pick next option, rather than selecting
			-- ["<Tab>"] = cmp.mapping(function(fallback)
			--   if cmp.visible() then
			--     cmp.select_next_item()
			--   elseif has_words_before() then
			--     cmp.complete()
			--   else
			--     fallback()
			--   end
			-- end, { "i", "s" }),

			-- luasnip change previous snippet field
			["<C-y>"] = cmp.mapping(function(fallback)
				if luasnip.jumpable(-1) then
					luasnip.jump(-1)
				else
					fallback()
				end
			end, { "i", "s" }),

			-- Copilot accept
			["<C-f>"] = cmp.mapping(function(_)
				vim.api.nvim_feedkeys(
					vim.fn["copilot#Accept"](vim.api.nvim_replace_termcodes("<Tab>", true, true, true)),
					"n",
					true
				)
			end),
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
