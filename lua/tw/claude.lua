local M = {}

local defaultArgs = {}

M.claude_buf = nil
M.claude_job_id = nil

local function open_vsplit_window()
  vim.api.nvim_command("vnew")
end

local function open_hsplit_window()
  vim.api.nvim_command("new")
end

local function open_editor_relative_window()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = vim.api.nvim_get_option("columns")
  local height = vim.api.nvim_get_option("lines")
  local win = vim.api.nvim_open_win(
    buf,
    true,
    { relative = "editor", width = width - 10, height = height - 10, row = 2, col = 2 }
  )
  vim.api.nvim_set_current_win(win)
end

local function open_window(window_type)
  if window_type == "vsplit" then
    open_vsplit_window()
  elseif window_type == "hsplit" then
    open_hsplit_window()
  else
    open_editor_relative_window()
  end
end

local function open_buffer_in_new_window(window_type, claude_buf)
  if window_type == "vsplit" then
    vim.api.nvim_command("vsplit | buffer " .. claude_buf)
  elseif window_type == "hsplit" then
    vim.api.nvim_command("split | buffer " .. claude_buf)
  else
    vim.api.nvim_command("buffer " .. claude_buf)
  end
end

local function OnExit(job_id, exit_code, event_type)
  vim.schedule(function()
    if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
      vim.api.nvim_buf_set_option(M.claude_buf, "modifiable", true)
      local message
      if exit_code == 0 then
        message = "Claude process completed successfully."
      else
        message = "Claude process exited with code: " .. exit_code
      end
      vim.api.nvim_buf_set_lines(M.claude_buf, -1, -1, false, { "", message })
      vim.api.nvim_buf_set_option(M.claude_buf, "modifiable", false)
    end
  end)
end

local get_claude_path = function()
  local handle = io.popen(table.concat({ "command", "-v", "claude" }, " "))
  local claude_path = ""
  if handle then
    local result = handle:read("*a")
    if result then
      claude_path = result:gsub("\n", "")
    end
    handle:close()
  end

  return claude_path
end

local function start_new_claude_job(args, window_type)
  local claude_path = get_claude_path()
  if claude_path == "" then
    vim.api.nvim_err_writeln("Claude executable not found in PATH")
    return
  end
  -- Disable auto update
  local configHandle = io.popen(table.concat({ claude_path, "config", "set", "-g", "autoUpdaterStatus", "disabled" }, " "))
  if configHandle then
    configHandle:close()
  end

  -- Launch Claude
  local cmd_args = ""
  if args and #args > 0 then
    cmd_args = table.concat(args, " ")
  end
  local command = claude_path .. " " .. cmd_args
  open_window(window_type)
  M.claude_buf = vim.api.nvim_get_current_buf()
  M.claude_job_id = vim.fn.termopen(command, {
    on_exit = OnExit,
    -- TODO: make this configurable
    env = {
      BUILD_IN_CONTAINER = "false",
    }
  })
  vim.bo[M.claude_buf].bufhidden = "hide"
  vim.bo[M.claude_buf].filetype = "ClaudeConsole"
  vim.cmd('startinsert')
end
function M.Open(args, window_type)
  args = args or defaultArgs
  window_type = window_type or "vsplit"
  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
    open_buffer_in_new_window(window_type, M.claude_buf)
  else
    start_new_claude_job(args, window_type)
  end
end

function M.SendCommand(args)
  if not M.claude_buf or not vim.api.nvim_buf_is_valid(M.claude_buf) then
    M.Open()

    -- Wait a bit for the Claude chat to initialize
    vim.defer_fn(function()
      M.SendCommand(args)
    end, 1000)
    return
  else
    -- Wait a bit after sending the !, otherwise the text is ignored
    vim.fn.chansend(M.claude_job_id, "!")
    vim.defer_fn(function()
      vim.fn.chansend(M.claude_job_id, table.concat(args, " "))
      -- TODO: Figure out how to get claude to accept an enter keypress
      vim.fn.chansend(M.claude_job_id, {""})
    end, 1000)
  end
end

function M.SendText(args)
  if not M.claude_buf or not vim.api.nvim_buf_is_valid(M.claude_buf) then
    M.Open()

    -- Wait a bit for the Claude chat to initialize
    vim.defer_fn(function()
      M.SendText(args)
    end, 1000)
    return
  else
    vim.fn.chansend(M.claude_job_id, table.concat(args, " "))
  end
end

function M.VimTestStrategy(cmd)
  M.SendCommand({ cmd })
end

local function configureClaudeKeymap()
  local claude = require("tw.claude")

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
  configureClaudeKeymap()
end

return M
