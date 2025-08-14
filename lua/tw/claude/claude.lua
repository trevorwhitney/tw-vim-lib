local M = {}

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

function M.command(args)
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


return M
