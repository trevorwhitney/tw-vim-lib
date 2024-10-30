local M = {}

local function configure()
  require('render-markdown').setup({
    file_types = { "markdown", "Avante" },
    latex = { enabled = false },
  })
  require('img-clip').setup(
    {
      -- recommended settings
      default = {
        embed_image_as_base64 = false,
        prompt_for_file_name = false,
        drag_and_drop = {
          insert_mode = true,
        },
        -- required for Windows users
        use_absolute_path = true,
      },
    })
  require('avante_lib').load()
  require('avante').setup({
    -- Your config here!
    {
      ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
      provider = "claude",                  -- Recommend using Claude
      auto_suggestions_provider = "copilot", -- Since auto-suggestions are a high-frequency operation and therefore expensive, it is recommended to specify an inexpensive provider or even a free provider: copilot
      hints = { enabled = false },
      -- defaults
      --
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-3-5-sonnet-20241022",
        temperature = 0,
        max_tokens = 4096,
      },
      --behaviour = {
      --  auto_suggestions = false, -- Experimental stage
      --  auto_set_highlight_group = true,
      --  auto_set_keymaps = true,
      --  auto_apply_diff_after_generation = false,
      --  support_paste_from_clipboard = false,
      --},
      --mappings = {
      --  --- @class AvanteConflictMappings
      --  diff = {
      --    ours = "co",
      --    theirs = "ct",
      --    all_theirs = "ca",
      --    both = "cb",
      --    cursor = "cc",
      --    next = "]x",
      --    prev = "[x",
      --  },
      --  suggestion = {
      --    accept = "<M-l>",
      --    next = "<M-]>",
      --    prev = "<M-[>",
      --    dismiss = "<C-]>",
      --  },
      --  jump = {
      --    next = "]]",
      --    prev = "[[",
      --  },
      --  submit = {
      --    normal = "<CR>",
      --    insert = "<C-s>",
      --  },
      --  sidebar = {
      --    switch_windows = "<Tab>",
      --    reverse_switch_windows = "<S-Tab>",
      --  },
      --},
      --windows = {
      --  ---@type "right" | "left" | "top" | "bottom"
      --  position = "right", -- the position of the sidebar
      --  wrap = true,        -- similar to vim.o.wrap
      --  width = 30,         -- default % based on available width
      --  sidebar_header = {
      --    align = "center", -- left, center, right for title
      --    rounded = true,
      --  },
      --},
      --highlights = {
      --  ---@type AvanteConflictHighlights
      --  diff = {
      --    current = "DiffText",
      --    incoming = "DiffAdd",
      --  },
      --},
      ----- @class AvanteConflictUserConfig
      --diff = {
      --  autojump = true,
      --  ---@type string | fun(): any
      --  list_opener = "copen",
      --},
    }
  })
end

local avante = require("avante.api")
local function configureKeymap()
  local keymap = {
    { "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>ca", function() avante.ask() end,  desc = "Avanate ask" },
      { "<leader>ce", function() avante.edit() end, desc = "Avanate edit" },
    },
    {
      mode = { "v" },
      { "<leader>cr", function() avante.refresh() end, desc = "Avante refresh" },
    },
  }

  local wk = require("which-key")
  wk.add(keymap)
end

function M.setup()
  configure()
  configureKeymap()
end

return M
