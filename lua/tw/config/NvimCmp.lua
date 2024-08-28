local M = {}

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
      if cmp.visible() and cmp.get_active_entry() then
        local confirm_opts = { behavior = cmp.ConfirmBehavior.Insert, select = false }
        cmp.confirm(confirm_opts)
      elseif luasnip.expandable() then
        luasnip.expand()
      else
        fallback()
      end
    end,
    s = cmp.mapping.confirm({ select = true }),
  })

  local selectPrevious = cmp.mapping(function(fallback)
    if cmp.visible() then
      cmp.select_prev_item()
    elseif luasnip.jumpable(-1) then
      luasnip.jump(-1)
    else
      fallback()
    end
  end, { "i", "s", "c" })
  local selectNext = function(fallback)
    if cmp.visible() then
      if #cmp.get_entries() == 1 then
        cmp.confirm({ select = true })
      else
        cmp.select_next_item()
      end
    elseif luasnip.locally_jumpable(1) then
      luasnip.jump(1)
    elseif has_words_before() then
      cmp.complete()
      if #cmp.get_entries() == 1 then
        cmp.confirm({ select = true })
      end
    else
      fallback()
    end
  end
  local selectNextCmdline = function()
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
  end
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
      ["<C-e>"] = cmp.mapping.abort(),
      ["<C-n>"] = cmp.mapping({
        i = selectNext,
        s = selectNext,
        c = selectNextCmdline,
      }),
      ["<Tab>"] = cmp.mapping({
        i = selectNext,
        s = selectNext,
        c = selectNextCmdline,
      }),
      ["<C-p>"] = selectPrevious,
      ["<S-Tab>"] = selectPrevious,
      ["<CR>"] = select,
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
