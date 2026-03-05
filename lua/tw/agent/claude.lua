local M = {}

local get_command_path = function(command_name)
	local handle = io.popen(table.concat({ "command", "-v", command_name }, " "))
	local command_path = ""
	if handle then
		local result = handle:read("*a")
		if result then
			command_path = result:gsub("\n", "")
		end
		handle:close()
	end

	return command_path
end

-- Build command for any AI coding assistant (claude, codex, opencode)
function M.command(args, command_name)
	command_name = command_name or "claude" -- Default to claude for backwards compatibility
	local command_path = get_command_path(command_name)
	if command_path == "" then
		vim.api.nvim_err_writeln(command_name .. " executable not found in PATH")
		return
	end

	-- Convert string to single-element table
	if type(args) == "string" then
		args = { args }
	elseif type(args) ~= "table" then
		args = {} -- Handle nil or other types
	end

	-- Create the base command table
	local command = {}

	-- Only set CLAUDE_CONFIG_DIR for claude and codex (not opencode)
	if command_name == "claude" or command_name == "codex" then
		table.insert(command, 'CLAUDE_CONFIG_DIR="${XDG_CONFIG_HOME}/claude"')
	end

	table.insert(command, command_path)

	-- Properly append all args to the command table
	for _, arg in ipairs(args) do
		table.insert(command, arg)
	end

	return table.concat(command, " ")
end

return M
