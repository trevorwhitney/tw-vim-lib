local M = {}

local claude = require("tw.claude.claude")
local mcps = require("tw.claude.mcps")
local Path = require("plenary.path")
local terminal = require("tw.claude.terminal")
local allowed_tools = require("tw.claude.allowed-tools")
local util = require("tw.claude.util")
local default_args = {
  '--allowedTools="' .. table.concat(allowed_tools, ",") .. '"',
}
--- Timer for checking file changes
--- @type userdata|nil
local refresh_timer = nil
M.claude_buf = nil
M.claude_job_id = nil
M.saved_updatetime = nil

-- Find the plugin installation path
local function get_plugin_root()
  local source = debug.getinfo(1, "S").source
  local file_path = string.sub(source, 2) -- Remove the '@' prefix
  local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/init%.lua$")
  return plugin_root
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


local function start_new_claude_job(args, window_type)
  -- Launch Claude
  local cmd_args = ""
  if args and #args > 0 then
    cmd_args = table.concat(args, " ")
  end
  local command = claude.command(cmd_args)
  terminal.open_window(window_type)
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

  vim.defer_fn(function()
    M.SendPrompt("coding.md")
    -- M.StartClaude()
    vim.cmd('startinsert')
  end, 1750)
end

local function submit()
  vim.defer_fn(function()
    vim.fn.chansend(M.claude_job_id, "\r")
  end, 500)
end

local function send(args)
  local text = ""
  if type(args) == "string" then
    -- Handle string argument
    text = args
  elseif type(args) == "table" and args and #args > 0 then
    -- Handle table argument
    text = table.concat(args, " ")
  end
  vim.fn.chansend(M.claude_job_id, text)
end

local function confirmOpenAndDo(callback, args, window_type)
  args = args or default_args
  window_type = window_type or "vsplit"
  if not M.claude_buf or not vim.api.nvim_buf_is_valid(M.claude_buf) then
    -- Buffer doesn't exist, open it
    M.Open(args, window_type)

    -- Wait a bit for the Claude chat to initialize
    vim.defer_fn(function()
      if callback then callback() end
    end, 1500)
  else
    -- Buffer exists, make sure it's visible
    local windows = vim.api.nvim_list_wins()
    local is_visible = false

    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
        -- Buffer is visible, hide it by closing the window
        is_visible = true
        break
      end
    end

    -- If buffer exists but is not visible, show it in a vsplit
    if not is_visible then
      terminal.open_buffer_in_new_window(window_type, M.claude_buf)
    end
    if callback then callback() end
  end
end

function M.Open(args, window_type)
  args = args or default_args
  window_type = window_type or "vsplit"
  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
    terminal.open_buffer_in_new_window(window_type, M.claude_buf)
  else
    start_new_claude_job(args, window_type)
  end
end

function M.Toggle(args, window_type)
  args = args or default_args
  window_type = window_type or "vsplit"
  -- If Claude buffer exists and is valid
  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
    -- Check if buffer is visible in any window
    local windows = vim.api.nvim_list_wins()
    local is_visible = false

    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
        -- Buffer is visible, hide it by closing the window
        vim.api.nvim_win_close(win, false)
        is_visible = true
        break
      end
    end

    -- If buffer exists but is not visible, show it in hsplit
    if not is_visible then
      terminal.open_buffer_in_new_window(window_type, M.claude_buf)
    end
  else
    -- Buffer doesn't exist, create it
    M.Open(args, window_type)
  end
end

function M.SendCommand(args)
  confirmOpenAndDo(function()
    vim.fn.chansend(M.claude_job_id, "!")
    vim.defer_fn(function()
      send(args)
      submit()
    end, 500)
  end)
end

function M.SendText(args)
  confirmOpenAndDo(function()
    send(args)
    submit()
  end)
end
function M.VimTestStrategy(cmd)
  M.SendCommand({ cmd })
end

local function sendCodeSnippet(args, rel_path)
  send({
    "For context, take a look at the following code snippet from @" .. rel_path .. "\n",
    "```\n",
  })
  send(args)
  send({
    "```\n",
    "Please load the file, making sure to caputre and understand the use of the code snippet, then wait for my instructions." })
  submit()
end

function M.SendSelection()
  -- Get the current selection
  vim.cmd('normal! "sy')

  -- Get the content of the register x
  local selection = vim.fn.getreg('s')

  -- Get the current file path
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(util.get_git_root())
  confirmOpenAndDo(function()
    -- Send the prompt
    sendCodeSnippet(selection, rel_path)

    -- Return to visual mode
    vim.cmd('normal! gv')
  end)
end

function M.SendSymbol()
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(util.get_git_root())
  local word = vim.fn.expand('<cword>')
  confirmOpenAndDo(function()
    M.SendText({
      "For context, take a look at the symbol",
      word,
      "from @" .. rel_path .. "\n",
      "Please load the file, making sure to caputre and understand the use of the symbol, then wait for my instructions."
    })
  end)
end

function M.SendFile()
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(util.get_git_root())
  confirmOpenAndDo(function()
    M.SendText({
      "For context, take a look at the file @" .. rel_path .. "\n",
      "Please load the file then wait for my instructions."
    })
  end)
end

function M.SendOpenBuffers()
  local files = util.get_buffer_files()

  if #files == 0 then
    vim.notify("No file buffers found to pass to Claude", vim.log.levels.WARN)
    return
  end

  confirmOpenAndDo(function()
    M.SendText({
      "For context, please load the following files:\n",
      table.concat(files, " ") .. "\n",
      "Load the files then wait for my instructions."
    })
  end)
end

function M.SendPrompt(filename)
  local plugin_root = get_plugin_root()
  local prompt_path = plugin_root .. "/prompts/" .. filename
  -- Read the prompt file
  local file = io.open(prompt_path, "r")
  if not file then
    vim.api.nvim_err_writeln("Could not find prompt file: " .. prompt_path)
    return
  end
  local content = file:read("*all")
  file:close()
  confirmOpenAndDo(function()
    M.SendText(content)
  end)
end
function M.StartClaude()
  confirmOpenAndDo(nil)
end

local function configureClaudeKeymap()
  local keymap = {
    { "<leader>c", group = "AI Code Assitant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>cl", function() require('tw.claude').Toggle() end, desc = "Toggle Claude" },
    },
    {
      mode = { "n" },
      { "<leader>tc", ":w<cr> :TestNearest -strategy=claude<cr>",                       desc = "Test Nearest (claude)",       nowait = false, remap = false },
      { "<leader>c*", function() require('tw.claude').SendSymbol() end,                 desc = "Send Current Word to Claude", nowait = false, remap = false },
      { "<leader>cf", function() require('tw.claude').SendFile() end,                   desc = "Send File to Claude",         nowait = false, remap = false },
      { "<leader>ct", function() require('tw.claude').SendPrompt("tdd-plan.md") end,    desc = "Send TDD Plan to Claude",     nowait = false, remap = false },
      { "<leader>cm", function() require('tw.claude').SendPrompt("commit-plan.md") end, desc = "Commit Staged with Claude",   nowait = false, remap = false },
      { "<leader>cb", function() require('tw.claude').SendOpenBuffers() end,            desc = "Send TDD Plan to Claude",     nowait = false, remap = false },
    },
    {
      mode = { "v" },
      {
        "<leader>c*",
        function() require('tw.claude').SendSelection() end,
        desc = "Send Selection to Claude",
        nowait = false,
        remap = false
      },
    }
  }

  local wk = require("which-key")
  wk.add(keymap)
end

function M.cleanup()
  if M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.claude_job_id)
    M.claude_job_id = nil
  end
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
    refresh_timer = nil
  end
end

-- adapted from https://github.com/greggh/claude-code.nvim/blob/main/lua/claude-code/file_refresh.lua
local function file_refresh()
  local augroup = vim.api.nvim_create_augroup('ClaudeCodeFileRefresh', { clear = true })

  -- Create an autocommand that checks for file changes more frequently
  vim.api.nvim_create_autocmd({
    'CursorHold',
    'CursorHoldI',
    'FocusGained',
    'BufEnter',
    'InsertLeave',
    'TextChanged',
    'TermLeave',
    'TermEnter',
    'BufWinEnter',
  }, {
    group = augroup,
    pattern = '*',
    callback = function()
      if vim.fn.filereadable(vim.fn.expand '%') == 1 then
        vim.cmd 'checktime'
      end
    end,
    desc = 'Check for file changes on disk',
  })

  -- Clean up any existing timer
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
    refresh_timer = nil
  end

  -- Create a timer to check for file changes periodically
  refresh_timer = vim.loop.new_timer()
  if refresh_timer then
    refresh_timer:start(
      0,
      1000, -- milliseconds
      vim.schedule_wrap(function()
        -- Only check time if there's an active Claude Code terminal
        local bufnr = M.claude_buf
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) > 0 then
          vim.cmd 'silent! checktime'
        end
      end)
    )
  end

  -- Create an autocommand that notifies when a file has been changed externally
  vim.api.nvim_create_autocmd('FileChangedShellPost', {
    group = augroup,
    pattern = '*',
    callback = function()
      vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.INFO)
    end,
    desc = 'Notify when a file is changed externally',
  })

  -- Set a shorter updatetime while Claude Code is open
  M.saved_updatetime = vim.o.updatetime

  -- When Claude Code opens, set a shorter updatetime
  vim.api.nvim_create_autocmd('TermOpen', {
    group = augroup,
    pattern = '*',
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match('claude%-code$') then
        M.saved_updatetime = vim.o.updatetime
        vim.o.updatetime = 100
      end
    end,
    desc = 'Set shorter updatetime when Claude Code is open',
  })

  -- When Claude Code closes, restore normal updatetime
  vim.api.nvim_create_autocmd('TermClose', {
    group = augroup,
    pattern = '*',
    callback = function()
      local buf_name = vim.api.nvim_buf_get_name(0)
      if buf_name:match('claude%-code$') then
        vim.o.updatetime = M.saved_updatetime
      end
    end,
    desc = 'Restore normal updatetime when Claude Code is closed',
  })
end

function M.setup()
  configureClaudeKeymap()
  file_refresh()

  mcps.install_mcps()

  local group = vim.api.nvim_create_augroup("Claude", { clear = true })
  -- Add cleanup for ClaudeConsole buffer
  -- Ensure cleanup on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.cleanup()
    end,
    group = group,
  })

  -- Set nowrap for Claude buffer windows, which makes code changes look better
  vim.api.nvim_create_autocmd("BufWinEnter", {
    callback = function(args)
      -- Check if this is the Claude buffer
      if M.claude_buf and args.buf == M.claude_buf then
        -- Set nowrap for the window displaying this buffer
        vim.wo[0].wrap = false
      end
    end,
    group = group,
  })
end

return M
