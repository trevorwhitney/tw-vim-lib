local M = {}

local SANDBOX_WRAPPER = vim.fn.expand("~/.config/sandbox-exec/run-sandboxed.sh")
local sandbox_available = vim.fn.executable(SANDBOX_WRAPPER) == 1
local sandbox_warned = false

-- Per-agent permission flags (unconditional — applied with and without sandbox)
local AGENT_FLAGS = {
	claude = { "--dangerously-skip-permissions" },
	codex = { "--full-auto" },
	-- opencode: no permission flags; it gets a dynamic --port (see below)
}

-- Ask the OS for a free TCP port by binding to port 0 and reading the assignment.
-- opencode agents launch with an explicit --port so they run a real, reachable
-- HTTP server that other agents can address via send-to-agent; without it,
-- opencode reports an unreachable placeholder URL to plugins. Returns nil if a
-- port cannot be obtained, in which case the agent still launches (messaging
-- just won't work for it). Exposed on M for test injection.
function M._free_port()
	local uv = vim.uv or vim.loop
	if not (uv and uv.new_tcp) then
		return nil
	end
	local tcp = uv.new_tcp()
	if not tcp then
		return nil
	end
	local port
	local ok = pcall(function()
		tcp:bind("127.0.0.1", 0)
		port = tcp:getsockname().port
	end)
	pcall(function()
		tcp:close()
	end)
	if ok then
		return port
	end
	return nil
end

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

	-- opencode: bind a real HTTP server on a free port so the agent is
	-- reachable by other agents (send-to-agent). Placed right after the binary,
	-- before positional args, mirroring the per-agent flag placement below.
	if command_name == "opencode" then
		local port = M._free_port()
		if port then
			table.insert(command, "--port")
			table.insert(command, tostring(port))
		end
	end

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
