local M = {}

local has_words_before = function()
  unpack = unpack or table.unpack
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local function configure()
  local cmp = require("cmp")
  local luasnip = require("luasnip")
  local suggestion = require("supermaven-nvim.completion_preview")
  local select = cmp.mapping({
    i = function(fallback)
      if cmp.visible() and cmp.get_selected_entry() then
        local confirm_opts = { behavior = cmp.ConfirmBehavior.Select, select = false }
        cmp.confirm(confirm_opts)
        if luasnip.jumpable(1) then
          luasnip.jump(1)
        end
      elseif luasnip.expandable() then
        luasnip.expand()
      elseif luasnip.jumpable(1) then
        luasnip.jump(1)
      elseif suggestion.has_suggestion() then
        suggestion.on_accept_suggestion()
      else
        fallback()
      end
    end,
    s = cmp.mapping.confirm({ select = true }),
    c = function(fallback)
      if cmp.visible() and cmp.get_selected_entry() then
        local confirm_opts = { behavior = cmp.ConfirmBehavior.Insert, select = false }
        cmp.confirm(confirm_opts)
      else
        fallback()
      end
    end,
  })

  local selectPreviousWithSnips = cmp.mapping(function(fallback)
    if cmp.visible() then
      cmp.select_prev_item()
    elseif luasnip.jumpable(-1) then
      luasnip.jump(-1)
    else
      fallback()
    end
  end, { "i", "s", "c" })

  local selectPreviousWithoutSnips = cmp.mapping(function(fallback)
    if cmp.visible() then
      cmp.select_prev_item()
    else
      fallback()
    end
  end, { "i", "s", "c" })

  local selectNextWithSnips = cmp.mapping(function(fallback)
    if cmp.visible() then
      if #cmp.get_entries() == 1 then
        cmp.confirm({ behavior = cmp.ConfirmBehavior.Select, select = true })
      else
        cmp.select_next_item()
      end
    elseif luasnip.jumpable(1) then
      luasnip.jump(1)
    elseif has_words_before() then
      cmp.complete()
      if #cmp.get_entries() == 1 then
        cmp.confirm({ select = true })
      end
    elseif suggestion.has_suggestion() then
      suggestion.on_accept_suggestion()
    else
      fallback()
    end
  end, { "i", "s", "c" })
  local selectNextWithoutSnips = cmp.mapping(function(fallback)
    if cmp.visible() then
      if #cmp.get_entries() == 1 then
        cmp.confirm({ select = true })
      else
        cmp.select_next_item()
      end
    elseif has_words_before() then
      cmp.complete()
      if #cmp.get_entries() == 1 then
        cmp.confirm({ select = true })
      end
    else
      fallback()
    end
  end, { "i", "s", "c" })
  cmp.setup({
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
      ["<C-e>"] = cmp.mapping.abort(),
      ["<C-n>"] = selectNextWithoutSnips,
      ["<Tab>"] = selectNextWithSnips,
      ["<C-p>"] = selectPreviousWithoutSnips,
      ["<S-Tab>"] = selectPreviousWithSnips,
      ["<CR>"] = select,

      -- luasnip forward and previous snippet field
      ["<C-u>"] = cmp.mapping(function(fallback)
        if luasnip.jumpable(1) then
          luasnip.jump(1)
        else
          fallback()
        end
      end, { "i", "s" }),
      ["<C-y>"] = cmp.mapping(function(fallback)
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { "i", "s" }),
    }),
    sources = cmp.config.sources({
      { name = "nvim_lsp" },
      { name = "nvim_lua" },
      { name = "path" },
      { name = "luasnip" },
      { name = "treesitter" },
      -- { name = "supermaven" },
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
