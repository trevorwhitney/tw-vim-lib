local M = {}

local Path = require("plenary.path")
local allowed_tools = {
  "Bash(awk:*)",
  "Bash(chmod:*)",
  "Bash(find:*)",
  "Bash(for i in:*)",
  "Bash(git branch:*)",
  "Bash(git config:*)",
  "Bash(git checkout:*)",
  "Bash(git cherry-pick:*)",
  "Bash(git fetch:*)",
  "Bash(git log:*)",
  "Bash(git rev-parse:*)",
  "Bash(git status:*)",
  "Bash(go build:*)",
  "Bash(go get:*)",
  "Bash(go run:*)",
  "Bash(go test:*)",
  "Bash(go vet:*)",
  "Bash(gofmt:*)",
  "Bash(grep:*)",
  "Bash(ls:*)",
  "Bash(make:*)",
  "Bash(mkdir:*)",
  "Bash(rg:*)",
  "Bash(sed:*)",
  "Bash(for i in:*)",
}

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
  local file_path = string.sub(source, 2)  -- Remove the '@' prefix
  local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/init%.lua$")
  return plugin_root
end

local function open_vsplit_window()
  vim.api.nvim_command("vert botright new")
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
    vim.api.nvim_command("vert botright split | buffer " .. claude_buf)
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

local function claudeCommand(args)
  local claude_path = get_claude_path()
  if claude_path == "" then
    vim.api.nvim_err_writeln("Claude executable not found in PATH")
    return
  end

  -- Convert string to single-element table
  if type(args) == "string" then
    args = { args }
  elseif type(args) ~= "table" then
    args = {} -- Handle nil or other types
  end

  -- Create the base command table
  local command = {
    'CLAUDE_CONFIG_DIR="${XDG_CONFIG_HOME}/claude"',
    claude_path
  }

  -- Properly append all args to the command table
  for _, arg in ipairs(args) do
    table.insert(command, arg)
  end

  return table.concat(command, " ")
end

local function start_new_claude_job(args, window_type)
  -- Launch Claude
  local cmd_args = ""
  if args and #args > 0 then
    cmd_args = table.concat(args, " ")
  end
  local command = claudeCommand(cmd_args)
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

  vim.defer_fn(function()
    M.PairProgramming()
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
      open_buffer_in_new_window(window_type, M.claude_buf)
    end
    if callback then callback() end
  end
end

function M.Open(args, window_type)
  args = args or default_args
  window_type = window_type or "vsplit"
  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
    open_buffer_in_new_window(window_type, M.claude_buf)
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
      open_buffer_in_new_window(window_type, M.claude_buf)
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
    "I would like to ask some question about this code snippet. Please load it but don't make any suggestions yet, just let me know when you're ready for my questions." })
  submit()
end

-- adapted from https://github.com/greggh/claude-code.nvim/blob/main/lua/claude-code/git.lua
local function get_git_root()
  -- Check if we're in a git repository
  local handle = io.popen('git rev-parse --is-inside-work-tree 2>/dev/null')
  if not handle then
    return nil
  end

  local result = handle:read('*a')
  handle:close()

  -- Strip trailing whitespace and newlines for reliable matching
  result = result:gsub('[\n\r%s]*$', '')

  if result == 'true' then
    -- Get the git root path
    local root_handle = io.popen('git rev-parse --show-toplevel 2>/dev/null')
    if not root_handle then
      return nil
    end

    local git_root = root_handle:read('*a')
    root_handle:close()

    -- Remove trailing whitespace and newlines
    git_root = git_root:gsub('[\n\r%s]*$', '')

    return git_root
  end

  return nil
end

function M.SendSelection()
  -- Get the current selection
  vim.cmd('normal! "sy')

  -- Get the content of the register x
  local selection = vim.fn.getreg('s')

  -- Get the current file path
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(get_git_root())

  confirmOpenAndDo(function()
    -- Send the prompt
    sendCodeSnippet(selection, rel_path)

    -- Return to visual mode
    vim.cmd('normal! gv')
  end)
end

function M.SendSymbol()
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(get_git_root())
  local word = vim.fn.expand('<cword>')

  confirmOpenAndDo(function()
    M.SendText({
      "For context, take a look at the symbol",
      word,
      "from @" .. rel_path .. "\n",
      "I would like to ask some question about this symbol. Please load it but don't make any suggestions yet, just let me know when you're ready for my questions."
    })
  end)
end

function M.SendFile()
  local filename = vim.fn.expand("%")
  local rel_path = Path:new(filename):make_relative(get_git_root())
  confirmOpenAndDo(function()
    M.SendText({
      "For context, take a look at the file @" .. rel_path .. "\n",
      "I would like to ask some question about this file. Please load it but don't make any suggestions yet, just let me know when you're ready for my questions."
    })
  end)
end

function M.PairProgramming()
  local plugin_root = get_plugin_root()
  -- local prompt_path = plugin_root .. "/prompts/pair-programming.md"
  local prompt_path = plugin_root .. "/prompts/coding.md"
  -- Read the pair programming prompt file
  local file = io.open(prompt_path, "r")
  if not file then
    vim.api.nvim_err_writeln("Could not find pair programming prompt file: " .. prompt_path)
    return
  end
  local content = file:read("*all")
  file:close()
  confirmOpenAndDo(function()
    M.SendText(content)
  end)
end
function M.TDDPlan()
  local plugin_root = get_plugin_root()
  -- local prompt_path = plugin_root .. "/prompts/pair-programming.md"
  local prompt_path = plugin_root .. "/prompts/tdd-plan.md"
  -- Read the pair programming prompt file
  local file = io.open(prompt_path, "r")
  if not file then
    vim.api.nvim_err_writeln("Could not find tdd plan prompt file: " .. prompt_path)
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
  local claude = require("tw.claude")
  local keymap = {
    { "<leader>c", group = "AI Code Assitant", nowait = true, remap = false },
    {
      mode = { "n", "v" },
      { "<leader>cl", claude.Toggle, desc = "Toggle Claude" },
    },
    {
      mode = { "n" },
      { "<leader>tc", ":w<cr> :TestNearest -strategy=claude<cr>", desc = "Test Nearest (claude)", nowait = false, remap = false },
      { "<leader>c*", claude.SendSymbol,                          desc = "Send Current Word to Claude", nowait = false, remap = false },
      { "<leader>cf", claude.SendFile,                            desc = "Send File to Claude",         nowait = false, remap = false },
      { "<leader>ct", claude.TDDPlan,                             desc = "Send TDD Plan to Claude",     nowait = false, remap = false },
    },
    {
      mode = { "v" },
      {
        "<leader>c*",
        claude.SendSelection,
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
