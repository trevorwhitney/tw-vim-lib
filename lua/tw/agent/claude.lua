local M = {}

local SANDBOX_WRAPPER = vim.fn.expand("~/.config/sandbox-exec/run-sandboxed.sh")
local sandbox_available = vim.fn.executable(SANDBOX_WRAPPER) == 1
local sandbox_warned = false

-- Per-agent permission flags (unconditional — applied with and without sandbox)
local AGENT_FLAGS = {
	claude = { "--dangerously-skip-permissions" },
	codex = { "--full-auto" },
	-- opencode: no flags needed
}

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
-- context_directories: table of {[abs_path] = true} for sandbox --add-dirs
function M.command(args, command_name, context_directories)
	command_name = command_name or "claude"
	local command_path = get_command_path(command_name)
	if command_path == "" then
		vim.api.nvim_err_writeln(command_name .. " executable not found in PATH")
		return
	end

	if type(args) == "string" then
		args = { args }
	elseif type(args) ~= "table" then
		args = {}
	end

	local command = {}

	-- Sandbox wrapper (if available)
	if sandbox_available then
		table.insert(command, SANDBOX_WRAPPER)

		-- --add-dirs for context directories (sorted for determinism)
		if context_directories and not vim.tbl_isempty(context_directories) then
			local dirs = vim.tbl_keys(context_directories)
			table.sort(dirs)
			table.insert(command, vim.fn.shellescape("--add-dirs=" .. table.concat(dirs, ":")))
		end
	else
		if not sandbox_warned then
			vim.notify(
				"Sandbox wrapper not found: " .. SANDBOX_WRAPPER .. " — running agent without sandbox",
				vim.log.levels.WARN
			)
			sandbox_warned = true
		end
	end

	-- Agent binary
	table.insert(command, command_path)

	-- Per-agent permission flags (unconditional)
	local flags = AGENT_FLAGS[command_name]
	if flags then
		for _, flag in ipairs(flags) do
			table.insert(command, flag)
		end
	end

	-- Caller-provided args
	for _, arg in ipairs(args) do
		table.insert(command, arg)
	end

	return table.concat(command, " ")
end

return M
