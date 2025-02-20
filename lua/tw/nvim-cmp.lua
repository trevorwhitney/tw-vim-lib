local M = {}

local function configure()
  local cmp = require("cmp")
  local luasnip = require("luasnip")
  local select = cmp.mapping({
    i = function(fallback)
      if cmp.visible() then
        if luasnip.expandable() then
          luasnip.expand()
        elseif cmp.get_selected_entry() then
          local confirm_opts = { behavior = cmp.ConfirmBehavior.Select, select = false }
          cmp.confirm(confirm_opts)
        end
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

  local function selectPrevious(snips)
    return cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif snips and luasnip.locally_jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { "i", "s", "c" })
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
    end, { "i", "s", "c" })
  end
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
      ["<C-n>"] = selectNext(false),
      ["<Tab>"] = selectNext(true),
      ["<C-p>"] = selectPrevious(false),
      ["<S-Tab>"] = selectPrevious(true),
      ["<CR>"] = select,
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
