local M = {}

-- Initialize log file path
local log_file = vim.fs.joinpath(vim.fn.stdpath('log'), 'claude.log')

-- Ensure log directory exists
vim.fn.mkdir(vim.fn.stdpath('log'), 'p')

-- Migrate old log file if it exists
local old_log_file = vim.fn.expand("~/.config/claude-nvim.log")
if vim.fn.filereadable(old_log_file) == 1 and vim.fn.filereadable(log_file) == 0 then
  vim.fn.rename(old_log_file, log_file)
end

-- Configuration
M.level = vim.log.levels.TRACE -- Default to maximum verbosity for debugging

-- Map vim.log.levels to string names for output
local level_names = {
  [vim.log.levels.TRACE] = "TRACE",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.ERROR] = "ERROR"
}

-- Internal logging function
local function write_log(level, message, notify)
  -- Only log if level meets threshold
  if level < M.level then
    return
  end

  local level_name = level_names[level] or "UNKNOWN"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format("[%s] %s: %s\n", timestamp, level_name, message)

  -- Use vim.schedule to make logging async-safe
  vim.schedule(function()
    local file, err = io.open(log_file, "a")
    if file then
      local ok, write_err = pcall(function()
        file:write(log_entry)
        file:close()
      end)
      if not ok and notify then
        vim.notify("Failed to write log: " .. tostring(write_err), vim.log.levels.ERROR)
      end
    elseif notify then
      vim.notify("Failed to open log file: " .. tostring(err), vim.log.levels.ERROR)
    end

    -- Send to vim.notify if requested
    if notify then
      vim.notify(message, level)
    end
  end)
end

-- Public API functions
function M.trace(message, notify)
  write_log(vim.log.levels.TRACE, message, notify)
end

function M.debug(message, notify)
  write_log(vim.log.levels.DEBUG, message, notify)
end

function M.info(message, notify)
  write_log(vim.log.levels.INFO, message, notify)
end

function M.warn(message, notify)
  write_log(vim.log.levels.WARN, message, notify)
end

function M.error(message, notify)
  write_log(vim.log.levels.ERROR, message, notify)
end

-- Get log file path
function M.get_log_file()
  return log_file
end

-- Set log level
function M.set_level(level)
  M.level = level
end

-- Get current log level name
function M.get_level_name()
  return level_names[M.level] or "UNKNOWN"
end

return M