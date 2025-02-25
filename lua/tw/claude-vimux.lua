local M = {}

local defaultArgs = {}

M.claude_started = false

function M.Open(args, window_type)
  if M.claude_started then
    return
  end

  args = args or defaultArgs

  -- Use 'which' to find the path to claude executable
  local handle = io.popen("which claude")
  local claude_path = ""
  if handle then
    local result = handle:read("*a")
    if result then
      claude_path = result:gsub("\n", "")
    end
    handle:close()
  end

  if claude_path == "" then
    vim.api.nvim_err_writeln("Claude executable not found in PATH")
    return
  end

  local cmd_args = ""
  if args and #args > 0 then
    cmd_args = table.concat(args, " ")
  end
  local command = claude_path .. " " .. cmd_args

  -- Open in vimux tmux window instead of buffer
  vim.fn["VimuxRunCommand"](command)

  -- No longer using buffer-based approach with the refactored implementation
  -- But keeping the buffer tracking for backward compatibility
  M.claude_started = true
end

function M.SendCommand(args)
  -- With vimux implementation, we need to send commands directly to the tmux pane
  local cmd_args = ""
  if args and #args > 0 then
    cmd_args = table.concat(args, " ")
  end

  -- Send ! followed by the command
  vim.fn["VimuxSendText"]("!")
  vim.defer_fn(function()
    vim.fn["VimuxSendText"](cmd_args)
    vim.fn["VimuxSendKeys"]("Enter")
  end, 1000)
end

function M.SendText(args)
  -- Send text directly to tmux pane
  local text = ""

  if type(args) == "string" then
    -- Handle string argument
    text = args
  elseif type(args) == "table" and args and #args > 0 then
    -- Handle table argument
    text = table.concat(args, " ")
  end

  vim.fn["VimuxSendText"](text)
end

function M.VimTestStrategy(cmd)
  M.SendCommand({ cmd })
end

local function configureClaudeKeymap()
  local claude = require("tw.claude-vimux")

  local keymap = {
    { "<leader>c", group = "AI Code Assitant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>cl", function() claude.Open() end, desc = "Open Claude" },
      { "<leader>c*", function() claude.SendText({vim.fn.expand('<cword>')}) end, desc = "Send Current Word to Claude", nowait = false, remap = false },
    },
    {
      mode = { "n" },
      { "<leader>tc", ":w<cr> :TestNearest -strategy=claude<cr>", desc = "Test Nearest (claude)", nowait = false, remap = false },
    }
  }

  local wk = require("which-key")
  wk.add(keymap)
end

function M.setup()
  -- Configure Vimux to use vertical split
  vim.g["VimuxOrientation"] = "h"
  vim.g["VimuxUseNearest"] = 0
  configureClaudeKeymap()
end

return M
