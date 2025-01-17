local M = {}

local function configure()
  -- Configure markdown rendering
  require('render-markdown').setup({
    file_types = { "markdown", "Avante" },
    latex = { enabled = false },
  })
  -- Configure image clipboard support
  require('img-clip').setup({
    default = {
      embed_image_as_base64 = false,
      prompt_for_file_name = false,
      drag_and_drop = { insert_mode = true },
      use_absolute_path = true, -- required for Windows users
    },
  })

  -- Load Avante library and configure
  require('avante_lib').load()
  require('avante').setup({
    provider = "claude",
    auto_suggestions_provider = "claude",
    hints = { enabled = false },
    claude = {
      endpoint = "https://api.anthropic.com",
      model = "claude-3-5-sonnet-20241022",
      temperature = 0,
      max_tokens = 4096,
    },
    -- gemini = {
    --   api_key = "your-gemini-api-key-here", -- Replace with your actual API key
    --   model = "gemini-pro",
    --   temperature = 0.7,
    --   max_tokens = 2048,
    -- },
    behaviour = {
      auto_set_keymaps = false,
    },
  })
end

-- Configure keymaps using which-key
local function configureKeymap()
  local avante = require("avante.api")
  local keymap = {
    { "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>ca", function() avante.ask() end, desc = "Avanate ask" },
    },
    {
      mode = { "n" },
      { "<leader>cr", function() avante.refresh() end, desc = "Avante refresh" },
      { "<leader>ct", function() avante.toggle() end,  desc = "Avante toggle" },
    },
    {
      mode = { "v" },
      { "<leader>ce", function() avante.edit() end, desc = "Avanate edit" },
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
