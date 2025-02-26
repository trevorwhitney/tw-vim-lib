local M = {}
local conform_format = require("conform").format
local function format(bufnr, options)
  local opts = options or {}
  opts = vim.tbl_deep_extend("force", opts, {
    async = false, -- this needs to stay false, otherwise the ranges clobber each other
    lsp_format = "first",
  })

  local ignore_filetypes = {
    "Trouble",
    "dap-repl",
    "dapui_console",
    "fugitive",
  }
  local buf_ft = vim.bo[bufnr].filetype
  if vim.tbl_contains(ignore_filetypes, buf_ft) then
    return
  end

  local lines = vim.fn.system("git diff --unified=0 " .. vim.fn.bufname(bufnr)):gmatch("[^\n\r]+")
  local ranges = {}
  for line in lines do
    if line:find("^@@") then
      local line_nums = line:match("%+.- ")
      if line_nums:find(",") then
        local _, _, first, second = line_nums:find("(%d+),(%d+)")
        first = tonumber(first)
        second = tonumber(second)
        if first and second then
          local end_line_pos = first + second - 1
          local end_line = vim.api.nvim_buf_get_lines(0, end_line_pos - 1, end_line_pos, true)[1]
          table.insert(ranges, {
            start = { first, 0 },
            ["end"] = { end_line_pos, end_line:len() - 1 },
          })
        end
      else
        local first = tonumber(line_nums:match("%d+"))
        if first then
          local end_line = vim.api.nvim_buf_get_lines(0, first, first + 1, true)[1]
          table.insert(ranges, {
            start = { first, 0 },
            ["end"] = { first + 1, end_line:len() - 1 },
          })
        end
      end
    end
  end

  if next(ranges) then
    for _, range in pairs(ranges) do
      local opt = vim.tbl_deep_extend("force", {
        range = range,
      }, opts)

      conform_format(opt, function(err, _)
        if not err == nil then
          vim.lsp.buf.format({ range = range })
        end
      end)
    end
  end
end

local function configure(use_eslint_daemon)
  local set = vim.opt
  set.formatexpr = "v:lua.require'conform'.formatexpr()"

  -- TODO: do something similar for prettierd vs prettier?
  local eslint = "eslint"
  if use_eslint_daemon then
    eslint = "eslint_d"
  end

  local formatters_by_ft = {
    bash = { "shfmt", "shellcheck" },
    -- these are all broken, do they not work with partial ranges?
    -- go = { "goimports", "gofmt", "gofumpt", "golines" },
    javascript = { eslint, "prettierd" },
    json = { "prettierd", "fixjson" },
    jsonnet = { "jsonnetfmt" },
    markdown = { "prettierd", "markdownlint" },
    nix = { "nixpkgs_fmt" },
    sh = { "shfmt", "shellcheck" },
    terraform = { "terraform_fmt" },
    typescript = { eslint, "prettierd" },
    -- prefer lua lsp formatting
    -- lua = { "stylua" },

    ["_"] = { "trim_whitespace", "trim_newlines" },
  }
  require("conform").setup({
    -- log_level = vim.log.levels.DEBUG,
    formatters_by_ft = formatters_by_ft,
    default_format_opts = {
      lsp_format = "first",
    },
  })
end

local function mapKeys()
  local wk = require("which-key")
  local keymap = {
    -- Formatting
    {
      mode = { "v", "x" },
      {
        "<leader>=",
        function()
          vim.cmd("update")
          local bufnr = vim.api.nvim_get_current_buf()
          local buf_ft = vim.bo[bufnr].filetype

          -- Go formatters are broken, I think because they don't support partial ranges.
          -- So conditionally run golines for a specifically selected range, otherwise rely on lsp formatting
          if buf_ft == "go" then
            require('conform').format({ async = false, lsp_format = "first", formatters = { "golines" } })
            return
          end

          require('conform').format({ async = false, lsp_format = "first" })
        end,
        desc = "Format",
        nowait = true,
        remap = false
      },
    },
    {
      mode = { "n" },
      {
        "<leader>=",
        function()
          vim.cmd("update")
          M.format()
        end,
        desc = "Format",
        nowait = true,
        remap = false
      },
      {
        "<leader>+",
        function()
          vim.cmd("update")
          require('conform').format({ async = false, lsp_format = "first" })
        end,
        desc = "Format",
        nowait = true,
        remap = false
      },
    },
  }

  wk.add(keymap)
end
function M.setup(use_eslint_daemon)
  configure(use_eslint_daemon)
  mapKeys()
end
function M.format(options)
  local opts = options or {}
  local bufnr = vim.api.nvim_get_current_buf()
  format(bufnr, opts)
end

return M
