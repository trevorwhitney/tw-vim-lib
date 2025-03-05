local M = {}

local Path = require("plenary.path")

---@param params avante.file_selector.opts.IGetFilepathsParams
local function get_filepaths(params)
  local cmd = { "sh", "-c", "git ls-files --others --cached --exclude-standard | grep -v '^vendor/' | grep -v '^.aider'" }
  local output = vim.system(cmd, { cwd = params.cwd, timeout = 5000 }):wait()
  if output.code ~= 0 then
    -- Print vim error line
    print(output.stderr)
    return {}
  end

  -- Split output into lines and filter empty lines
  local files = vim.split(output.stdout, '\n')

  return vim.tbl_map(function(path)
    local rel_path = Path:new(path):make_relative(params.cwd)
      local stat = vim.loop.fs_stat(path)
    if stat and stat.type == "directory" then rel_path = rel_path .. "/" end
    return rel_path
    end, files)
end

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
    file_selector = {
      provider = "telescope",
      provider_opts = {
        get_filepaths = get_filepaths,
      },
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
      { "<leader>cc", function() avante.ask() end, desc = "Avanate ask" },
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
