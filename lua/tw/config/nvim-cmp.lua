local has_words_before = function()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local cmp = require("cmp")
cmp.setup({
  snippet = {
    -- We recommend using *actual* snippet engine.
    -- It's a simple implementation so it might not work in some of the cases.
    expand = function(args)
      local line_num, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line_text = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, true)[1]
      local indent = string.match(line_text, "^%s*")
      local replace = vim.split(args.body, "\n", true)
      local surround = string.match(line_text, "%S.*") or ""
      local surround_end = surround:sub(col)

      replace[1] = surround:sub(0, col - 1) .. replace[1]
      replace[#replace] = replace[#replace] .. (#surround_end > 1 and " " or "") .. surround_end
      if indent ~= "" then
        for i, line in ipairs(replace) do
          replace[i] = indent .. line
        end
      end

      vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, replace)
    end,
  },

  mapping = cmp.mapping.preset.insert({
    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
    ["<C-f>"] = cmp.mapping.scroll_docs(4),
    ["<C-e>"] = cmp.mapping.abort(),
    ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.

    ["<Tab>"] = function(fallback)
      if not cmp.select_next_item() then
        if vim.bo.buftype ~= "prompt" and has_words_before() then
          cmp.complete()
        else
          fallback()
        end
      end
    end,

    ["<S-Tab>"] = function(fallback)
      if not cmp.select_prev_item() then
        if vim.bo.buftype ~= "prompt" and has_words_before() then
          cmp.complete()
        else
          fallback()
        end
      end
    end,

    -- Copilot accept
    ["<C-j>"] = cmp.mapping(function(_)
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
    -- { name = "calc" },
    -- { name = "emoji" },
  }, {
    { name = "buffer" },
  }),
})
