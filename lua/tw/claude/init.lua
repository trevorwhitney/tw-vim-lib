local M = {}

local claude = require("tw.claude.claude")
local docker = require("tw.claude.docker")
local Path = require("plenary.path")
local terminal = require("tw.claude.terminal")
local allowed_tools = require("tw.claude.allowed-tools")
local util = require("tw.claude.util")
local log = require("tw.log")
local default_args = {}

-- Expose log module globally for claude.lua to use
_G.claude_log = log
--- Timer for checking file changes
--- @type userdata|nil
local refresh_timer = nil
M.claude_buf = nil
M.claude_job_id = nil
M.saved_updatetime = nil
M.shell_buf = nil
M.shell_job_id = nil
M.logs_buf = nil
M.logs_job_id = nil

-- Docker mode configuration
M.docker_mode = true        -- DEFAULT TO DOCKER MODE
M.auto_build = true         -- Auto-build image if missing
M.container_started = false -- Track if we started the container
M.container_name = string.format("claude-code-nvim-%d-%d", vim.fn.getpid(), os.time()) -- More unique container name
-- Auto-prompt configuration
M.auto_prompt = true             -- Send prompt automatically on startup
M.auto_prompt_file = "coding.md" -- Default prompt file to send

-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount at /context/*

-- Helper function for terminal buffer management
local function open_or_reuse_terminal_buffer(buf_var_name, window_type)
  local buf = M[buf_var_name]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    -- Check if buffer is visible in any window
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_set_current_win(win)
        vim.cmd('startinsert')
        return true, buf
      end
    end
    -- Buffer exists but not visible, show it
    terminal.open_buffer_in_new_window(window_type or "vsplit", buf)
    vim.cmd('startinsert')
    return true, buf
  end
  return false, nil
end

-- Find the plugin installation path
local function get_plugin_root()
  local source = debug.getinfo(1, "S").source
  local file_path = string.sub(source, 2) -- Remove the '@' prefix
  local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/init%.lua$")
  return plugin_root
end



-- Helper function to cleanly close Claude buffer and clear state
local function close_claude_buffer()
  -- Stop the job if it's running
  if M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.claude_job_id)
  end

  -- Close any windows showing the Claude buffer
  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
        vim.api.nvim_win_close(win, true)
      end
    end
    -- Delete the buffer
    vim.api.nvim_buf_delete(M.claude_buf, { force = true })
  end

  -- Clear the state
  M.claude_buf = nil
  M.claude_job_id = nil
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
    -- Clear buffer and job state when process exits
    M.claude_buf = nil
    M.claude_job_id = nil
  end)
end

local function start_new_claude_job(args, window_type)
  log.info("Attempting to start new Claude job")
  -- Launch Claude
  local command
  if M.docker_mode then
    log.debug("Docker mode enabled, checking container status")
    -- Check if container is running, if not try to start it
    local is_running, container_id, status = docker.is_container_running(M.container_name)
    log.debug("Container running check result: " .. tostring(is_running))
    log.debug("Container ID: " .. (container_id or "none"))
    log.debug("Container status: " .. (status or "unknown"))
    log.debug("Container started flag: " .. tostring(M.container_started))

    if not is_running then
      if M.container_started then
        -- Container was started but isn't running - try to restart it
        log.warn("Container was started but is not running, attempting restart", true)
        docker.ensure_container_stopped(M.container_name)
        local success, result = docker.start_persistent_container(M.container_name)
        if not success then
          log.error("Failed to restart container: " .. (result or "Unknown error"), true)
          M.docker_mode = false
          M.container_started = false
        end
      else
        log.error("Container not running and not started by this session", true)
        return
      end
    end

    local cmd_args = ""
    if args and #args > 0 then
      cmd_args = table.concat(args, " ")
    end
    command = docker.attach_to_container(M.container_name, cmd_args)
    log.debug("Using attach command: " .. command)
  else
    log.debug("Native mode enabled")
    -- For non-docker mode, include allowedTools
    local final_args = vim.tbl_extend("force", {}, default_args)
    table.insert(final_args, '--allowedTools="' .. table.concat(allowed_tools, ",") .. '"')
    if args and #args > 0 then
      vim.list_extend(final_args, args)
    end
    command = claude.command(final_args)
    log.debug("Using native command: " .. command)
  end
  log.info("Starting Claude with command: " .. command)
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

  -- Auto-send prompt if enabled (works for both Docker and native modes)
  if M.auto_prompt and M.auto_prompt_file then
    vim.defer_fn(function()
      log.debug("Sending auto-prompt: " .. M.auto_prompt_file)
      M.SendPrompt(M.auto_prompt_file, true)
      vim.cmd('startinsert')
    end, 1750)
  else
    vim.defer_fn(function()
      vim.cmd('startinsert')
    end, 500)
  end
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
  
  -- Check if buffer exists, is valid, AND the job is still running
  local job_is_running = M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1

  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) and job_is_running then
    terminal.open_buffer_in_new_window(window_type, M.claude_buf)
  else
    -- Clean up dead buffer if needed
    if M.claude_buf and not job_is_running then
      close_claude_buffer()
    end
    start_new_claude_job(args, window_type)
  end
end

function M.Toggle(args, window_type)
  args = args or default_args
  window_type = window_type or "vsplit"
  
  -- Check if buffer exists, is valid, AND the job is still running
  local job_is_running = M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1

  if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) and job_is_running then
    -- Buffer exists and job is running - toggle visibility
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

    -- If buffer exists but is not visible, show it in window_type
    if not is_visible then
      terminal.open_buffer_in_new_window(window_type, M.claude_buf)
    end
  else
    -- Buffer doesn't exist or job is dead, clean up and create new
    if M.claude_buf and not job_is_running then
      close_claude_buffer() -- Clean up dead buffer
    end
    M.Open(args, window_type)
  end
end

local function submit()
  vim.defer_fn(function()
    vim.fn.chansend(M.claude_job_id, "\r")
  end, 500)
end

function M.SendCommand(args, submit_after)
  submit_after = submit_after or false
  confirmOpenAndDo(function()
    vim.fn.chansend(M.claude_job_id, "!")
    vim.defer_fn(function()
      send(args)
      if submit_after then
        submit()
      end
    end, 500)
  end)
end

function M.SendText(args, submit_after)
  submit_after = submit_after or false
  confirmOpenAndDo(function()
    send(args)
    if submit_after then
      submit()
    end
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
  -- submit()
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

function M.SendPrompt(filename, submit_after)
  submit_after = submit_after or false
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
    M.SendText(content, submit_after)
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
      { "<leader>cm", function() require('tw.claude').SendPrompt("commit-staged.md") end, desc = "Commit Staged with Claude",   nowait = false, remap = false },
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

function M.start_container_async()
  log.info("Starting Claude container startup process", true)
  -- First build image if needed (async)
  if M.auto_build and not docker.check_docker_image() then
    log.info("Docker image not found, starting build process", true)
    local build_cmd = docker.build_docker_image()
    log.debug("Build command: " .. build_cmd)

    vim.fn.jobstart(build_cmd, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          log.debug("Build process exit code: " .. exit_code)
          if exit_code ~= 0 then
            log.error("Failed to build Docker image, exit code: " .. exit_code, true)
            M.docker_mode = false
            return
          end
          log.info("Docker image built successfully", true)
          -- Now start the container
          M.start_container_after_build()
        end)
      end,
      on_stdout = function(_, data)
        -- Log and show build progress
        if data and #data > 0 then
          for _, line in ipairs(data) do
            if line and line ~= "" then
              log.debug("Build output: " .. line)
              print("Build: " .. line)
            end
          end
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 then
          for _, line in ipairs(data) do
            if line and line ~= "" then
              log.error("Build error: " .. line)
            end
          end
        end
      end,
    })
  else
    log.info("Docker image exists, proceeding to container startup")
    -- Image exists, start container directly
    M.start_container_after_build()
  end
end

function M.start_container_after_build()
  log.info("Starting container cleanup and startup process")
  -- Ensure any existing container is stopped (async)
  local cleanup_cmd = "docker rm -f " .. M.container_name .. " 2>/dev/null"
  log.debug("Cleanup command: " .. cleanup_cmd)

  vim.fn.jobstart(cleanup_cmd, {
    on_exit = function(_, cleanup_exit_code)
      vim.schedule(function()
        log.debug("Cleanup exit code: " .. cleanup_exit_code)
        -- Now start the persistent container
        local start_cmd = docker.get_start_container_command(M.container_name, M.context_directories)
        log.debug("Container start command: " .. start_cmd)
        vim.fn.jobstart(start_cmd, {
          on_exit = function(_, exit_code)
            vim.schedule(function()
              log.debug("Container start exit code: " .. exit_code)
              if exit_code == 0 then
                -- Container started, but need to verify it's actually running
                vim.defer_fn(function()
                  local is_running, container_id, container_status = docker.is_container_running(M.container_name)
                  log.debug("Container verification - running: " .. tostring(is_running))
                  log.debug("Container verification - ID: " .. (container_id or "none"))
                  log.debug("Container verification - status: " .. (container_status or "unknown"))

                  if is_running then
                    M.container_started = true
                    log.info("Container verified running, setting up firewall...")

                    -- Set up firewall after successful container start
                    vim.defer_fn(function()
                      log.info("Starting container firewall setup...")
                      docker.setup_container_firewall(M.container_name, function(firewall_success)
                        -- This callback runs after firewall setup (success or failure)
                        local security_status = firewall_success and " (secured)" or " (limited security)"
                        log.info("Claude container fully ready" .. security_status, true)
                      end)
                    end, 2000) -- Wait 2 seconds after container verification to set up firewall
                  else
                    log.error("Container started but is not running - status: " .. (container_status or "unknown"), true)
                    M.docker_mode = false
                  end
                end, 1000) -- Wait 1 second for container to fully initialize
              else
                log.error("Failed to start Claude container, exit code: " .. exit_code, true)
                M.docker_mode = false
              end
            end)
          end,
          on_stdout = function(_, data)
            if data and #data > 0 then
              for _, line in ipairs(data) do
                if line and line ~= "" then
                  log.debug("Container start output: " .. line)
                end
              end
            end
          end,
          on_stderr = function(_, data)
            if data and #data > 0 then
              for _, line in ipairs(data) do
                if line and line ~= "" then
                  log.error("Container start error: " .. line)
                end
              end
            end
          end,
        })
      end)
    end,
  })
end
function M.cleanup()
  if M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.claude_job_id)
    M.claude_job_id = nil
  end
  if M.shell_job_id and vim.fn.jobwait({ M.shell_job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.shell_job_id)
    M.shell_job_id = nil
  end
  if M.logs_job_id and vim.fn.jobwait({ M.logs_job_id }, 0)[1] == -1 then
    vim.fn.jobstop(M.logs_job_id)
    M.logs_job_id = nil
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

function M.setup(opts)
  opts = opts or {}
  M.docker_mode = opts.docker_mode ~= false -- Docker mode unless explicitly disabled
  M.auto_build = opts.auto_build ~= false
  
  -- Log the container name for this instance
  if M.docker_mode then
    log.info("Neovim instance PID " .. vim.fn.getpid() .. " will use container: " .. M.container_name)
  end

  -- Configure auto-prompt
  if opts.auto_prompt ~= nil then
    M.auto_prompt = opts.auto_prompt
  end
  if opts.auto_prompt_file then
    M.auto_prompt_file = opts.auto_prompt_file
  end

  -- Configure logging
  if opts.log_level then
    log.set_level(opts.log_level)
  end
  configureClaudeKeymap()
  file_refresh()

  local group = vim.api.nvim_create_augroup("Claude", { clear = true })
  -- Start container on Vim startup if in docker mode (async)
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      if M.docker_mode then
        log.info("VimEnter triggered, Docker mode enabled")
        vim.defer_fn(function()
          log.info("Starting async container startup after delay")
          M.start_container_async()
        end, 100) -- Small delay to let Neovim finish startup
      else
        log.info("VimEnter triggered, Docker mode disabled")
      end
    end,
    group = group,
  })
  -- Ensure cleanup on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.cleanup()
      if M.docker_mode and M.container_started then
        docker.stop_container(M.container_name)
        M.container_started = false
      end
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
  -- Add Docker commands
  vim.api.nvim_create_user_command("ClaudeDockerToggle", function()
    if M.docker_mode then
      -- Switching from docker to native mode
      if M.container_started then
        close_claude_buffer()  -- Clean up Claude buffer before switching modes
        docker.stop_container(M.container_name)
        M.container_started = false
      end
      M.docker_mode = false
      vim.notify("Claude Docker mode: disabled (container " .. M.container_name .. ")")
    else
      -- Switching from native to docker mode
      M.docker_mode = true
      vim.notify("Claude Docker mode: enabled - starting container " .. M.container_name .. "...")
      -- Start container asynchronously
      M.start_container_async()
    end
  end, { desc = "Toggle between Docker and native Claude mode" })

  vim.api.nvim_create_user_command("ClaudeDockerBuild", function()
    local cmd = docker.build_docker_image()
    log.info("Manual Docker image build initiated", true)
    vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      log.info("Docker image built successfully (manual)", true)
    else
      log.error("Failed to build Docker image (manual)", true)
    end
  end, { desc = "Build the Claude Docker image" })

  vim.api.nvim_create_user_command("ClaudeDockerRestart", function()
    if not M.docker_mode then
      vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
      return
    end

    log.info("Manual container restart initiated", true)

    -- Stop current container
    if M.container_started then
      close_claude_buffer()  -- Clean up Claude buffer before restart
      docker.stop_container(M.container_name)
      M.container_started = false
      log.info("Stopped existing container")
    end

    -- Start new container
    M.start_container_async()
  end, { desc = "Restart the Claude Docker container" })

  vim.api.nvim_create_user_command("ClaudeAddContext", function(args)
    local dir_path = vim.fn.expand(args.args)

    -- Validate directory exists
    if vim.fn.isdirectory(dir_path) == 0 then
      vim.notify("Directory does not exist: " .. dir_path, vim.log.levels.ERROR)
      return
    end

    -- Get absolute path
    local abs_path = vim.fn.fnamemodify(dir_path, ":p:h") -- :h removes trailing slash

    -- Check if already added
    if M.context_directories[abs_path] then
      vim.notify("Context already added: " .. abs_path, vim.log.levels.INFO)
      return
    end

    -- Add to context directories
    M.context_directories[abs_path] = true
    log.info("Added context directory: " .. abs_path)

    -- Restart container with new mounts
    if M.docker_mode and M.container_started then
      vim.notify("Restarting container with new context: " .. abs_path)
      close_claude_buffer() -- Clean up Claude buffer before restart
      docker.stop_container(M.container_name)
      M.container_started = false
      M.start_container_async()
    else
      vim.notify("Context will be mounted when container starts: " .. abs_path)
    end
  end, {
    nargs = 1,
    complete = "dir",
    desc = "Add a directory to mount in Claude container at /context"
  })

  vim.api.nvim_create_user_command("ClaudeRemoveContext", function(args)
    local dir_path = vim.fn.expand(args.args)
    local abs_path = vim.fn.fnamemodify(dir_path, ":p:h") -- :h removes trailing slash

    if not M.context_directories[abs_path] then
      vim.notify("Context not found: " .. abs_path, vim.log.levels.WARN)
      return
    end

    -- Remove from context directories
    M.context_directories[abs_path] = nil
    log.info("Removed context directory: " .. abs_path)

    -- Restart container if running
    if M.docker_mode and M.container_started then
      vim.notify("Restarting container without context: " .. abs_path)
      close_claude_buffer() -- Clean up Claude buffer before restart
      docker.stop_container(M.container_name)
      M.container_started = false
      M.start_container_async()
    else
      vim.notify("Context removed: " .. abs_path)
    end
  end, {
    nargs = 1,
    complete = function()
      local contexts = {}
      for path, _ in pairs(M.context_directories) do
        table.insert(contexts, path)
      end
      return contexts
    end,
    desc = "Remove a context directory from Claude container"
  })

  vim.api.nvim_create_user_command("ClaudeListContexts", function()
    if vim.tbl_isempty(M.context_directories) then
      vim.notify("No context directories mounted", vim.log.levels.INFO)
      return
    end

    local lines = { "Context directories mounted in container:" }
    local i = 1
    for source_path, _ in pairs(M.context_directories) do
      local dir_name = vim.fn.fnamemodify(source_path, ":t")
      -- Check for duplicates to show actual mount name
      local mount_name = dir_name
      local has_duplicate = false
      for other_path, _ in pairs(M.context_directories) do
        if other_path ~= source_path and vim.fn.fnamemodify(other_path, ":t") == dir_name then
          has_duplicate = true
          break
        end
      end
      if has_duplicate then
        local hash = vim.fn.sha256(source_path)
        mount_name = dir_name .. "_" .. string.sub(hash, 1, 8)
      end
      table.insert(lines, string.format("  %d. %s -> /context/%s", i, source_path, mount_name))
      i = i + 1
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "List all context directories mounted in Claude container" })

  vim.api.nvim_create_user_command("ClaudeDockerShell", function()
    if not M.docker_mode then
      vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
      return
    end

    if not docker.is_container_running(M.container_name) then
      vim.notify("Claude container is not running. Start it first.", vim.log.levels.ERROR)
      return
    end

    log.info("Opening shell in Claude container")

    local found, _ = open_or_reuse_terminal_buffer("shell_buf", "vsplit")
    if not found then
      -- Create new shell terminal
      terminal.open_window("vsplit")
      M.shell_buf = vim.api.nvim_get_current_buf()

      -- Start shell in container
      M.shell_job_id = vim.fn.termopen("docker exec -it " .. M.container_name .. " /bin/bash", {
        on_exit = function(_, exit_code)
          log.debug("Container shell exited with code: " .. exit_code)
          M.shell_buf = nil
          M.shell_job_id = nil
        end
      })

      vim.bo[M.shell_buf].bufhidden = "hide"
      vim.bo[M.shell_buf].filetype = "ClaudeShell"
      vim.cmd('startinsert')
    end
  end, { desc = "Open a shell inside the Claude Docker container" })

  -- Add log viewing commands
  vim.api.nvim_create_user_command("ClaudeShowLog", function()
    local log_file = log.get_log_file()
    if vim.fn.filereadable(log_file) == 1 then
      vim.cmd("tabnew " .. vim.fn.fnameescape(log_file))
      vim.bo.filetype = "log"
      -- Jump to end of file to see latest entries
      vim.cmd("normal! G")
    else
      vim.notify("Claude log file not found: " .. log_file, vim.log.levels.WARN)
    end
  end, { desc = "Show Claude container log file" })

  vim.api.nvim_create_user_command("ClaudeContainerLogs", function()
    if not M.docker_mode then
      vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
      return
    end

    if not docker.is_container_running(M.container_name) then
      vim.notify("Claude container is not running. Start it first.", vim.log.levels.ERROR)
      return
    end

    log.info("Opening Claude container logs")

    local found, _ = open_or_reuse_terminal_buffer("logs_buf", "vsplit")
    if not found then
      -- Create new logs terminal
      terminal.open_window("vsplit")
      M.logs_buf = vim.api.nvim_get_current_buf()

      -- Show logs from container (check claude-cli-nodejs cache directory)
      M.logs_job_id = vim.fn.termopen(
        "docker exec -it " .. M.container_name .. " /bin/bash -c 'for dir in /home/node/.cache/claude-cli-nodejs/-workspace /home/node/.cache/claude-cli-nodejs; do if [ -d \"$dir\" ]; then find \"$dir\" -name \"*.log\" -type f -exec echo \"=== {} ===\" \\; -exec cat {} \\; -exec echo \"\" \\; 2>/dev/null; fi; done || echo \"No log files found\"'",
        {
          on_exit = function(_, exit_code)
            log.debug("Container logs command exited with code: " .. exit_code)
            M.logs_buf = nil
            M.logs_job_id = nil
          end
        })

      vim.bo[M.logs_buf].bufhidden = "hide"
      vim.bo[M.logs_buf].filetype = "log"
      vim.cmd('startinsert')
    end
  end, { desc = "Show Claude CLI logs from inside the Docker container" })

  vim.api.nvim_create_user_command("ClaudeLogLevel", function(args)
    local level_map = {
      TRACE = vim.log.levels.TRACE,
      DEBUG = vim.log.levels.DEBUG,
      INFO = vim.log.levels.INFO,
      WARN = vim.log.levels.WARN,
      ERROR = vim.log.levels.ERROR,
      OFF = vim.log.levels.OFF
    }

    if args.args == "" then
      local current = log.get_level_name()
      vim.notify("Current Claude log level: " .. current)
      return
    end
    local new_level = level_map[string.upper(args.args)]
    if new_level then
      log.set_level(new_level)
      vim.notify("Claude log level set to: " .. string.upper(args.args))
      log.info("Log level changed to: " .. string.upper(args.args))
    else
      vim.notify("Invalid log level. Use: TRACE, DEBUG, INFO, WARN, ERROR, OFF", vim.log.levels.ERROR)
    end
  end, {
    desc = "Set or show Claude log level",
    nargs = "?",
    complete = function()
      return { "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
    end
  })
end
return M
