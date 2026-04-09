local M = {}

local docker = require("tw.agent.docker")
local terminal = require("tw.agent.terminal")
local buffer_config = require("tw.agent.buffer-config")
local log = require("tw.log")

-- Timer for checking file changes
local refresh_timer = nil

-- Setup autocmds for file refresh and other events
function M.setup_autocmds(claude_module)
	local group = vim.api.nvim_create_augroup("Claude", { clear = true })

	-- Ensure cleanup on Neovim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			claude_module.cleanup()
			if claude_module.container_started then
				-- Stop container asynchronously to avoid hanging vim on exit
				-- Fork the docker stop command so vim can exit immediately
				local stop_cmd = string.format(
					"docker stop %s 2>/dev/null && docker rm %s 2>/dev/null &",
					claude_module.container_name,
					claude_module.container_name
				)
				-- Use io.popen with & to run in background
				io.popen(stop_cmd)
				claude_module.container_started = false
			end
		end,
		group = group,
	})

	-- Detect workmux prompt file on startup
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = function()
			-- Slight delay to let vim fully initialize
			vim.defer_fn(function()
				claude_module.WorkmuxPrompt()
			end, 100)
		end,
		group = group,
		desc = "Detect and send workmux prompt to agent on startup",
	})

	-- When workmux opened opencode fullscreen, revert to vsplit layout
	-- the first time a non-terminal buffer is entered (e.g. editing a file).
	vim.api.nvim_create_autocmd("BufEnter", {
		callback = function(args)
			if not claude_module.workmux_fullscreen then
				return
			end

			-- Only act on normal (non-terminal) buffers
			local buftype = vim.bo[args.buf].buftype
			if buftype == "terminal" then
				return
			end

			-- Disable the flag so this only fires once
			claude_module.workmux_fullscreen = false

			-- Find the opencode agent buffer
			local agent_buf = claude_module.opencode_buf or claude_module.opencode_docker_buf
			if not agent_buf or not vim.api.nvim_buf_is_valid(agent_buf) then
				return
			end

			-- The file buffer is now in the current window. Open the agent
			-- buffer in a right-side vsplit so the layout becomes:
			--   [file (left)]  |  [opencode (right)]
			terminal.open_buffer_in_new_window("vsplit", agent_buf)

			-- Move focus back to the file window (the previous window)
			vim.cmd("wincmd p")
		end,
		group = group,
		desc = "Revert workmux fullscreen opencode to vsplit when a file is opened",
	})

	-- Set nowrap for agent buffer windows, which makes code changes look better
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			-- Check if this is an agent buffer
			local all_modes = { "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker" }
			for _, mode in ipairs(all_modes) do
				local var_name = mode:gsub("-", "_")
				local buf_key = var_name .. "_buf"
				if claude_module[buf_key] and args.buf == claude_module[buf_key] then
					-- Set nowrap for the window displaying this buffer
					vim.wo[0].wrap = false
					break
				end
			end
		end,
		group = group,
	})

	-- File refresh autocmds
	local refresh_group = vim.api.nvim_create_augroup("ClaudeCodeFileRefresh", { clear = true })

	-- Create an autocommand that checks for file changes more frequently
	vim.api.nvim_create_autocmd({
		"CursorHold",
		"CursorHoldI",
		"FocusGained",
		"BufEnter",
		"InsertLeave",
		"TextChanged",
		"TermLeave",
		"TermEnter",
		"BufWinEnter",
	}, {
		group = refresh_group,
		pattern = "*",
		callback = function()
			if vim.fn.filereadable(vim.fn.expand("%")) == 1 then
				vim.cmd("checktime")
			end
		end,
		desc = "Check for file changes on disk",
	})

	-- Clean up any existing timer
	if refresh_timer then
		refresh_timer:stop()
		refresh_timer:close()
		refresh_timer = nil
	end

	-- Create a timer to check for file changes periodically
	refresh_timer = vim.uv.new_timer()
	if refresh_timer then
		refresh_timer:start(
			0,
			1000, -- milliseconds
			vim.schedule_wrap(function()
				-- Only check time if there's an active agent terminal
				local any_visible = false
				local all_modes = { "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker" }
				for _, mode in ipairs(all_modes) do
					local var_name = mode:gsub("-", "_")
					local buf_key = var_name .. "_buf"
					local buf = claude_module[buf_key]
					if buf and vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
						any_visible = true
						break
					end
				end
				if any_visible then
					vim.cmd("silent! checktime")
				end
			end)
		)
	end

	-- Store timer reference in module for cleanup
	claude_module._refresh_timer = refresh_timer

	-- Create an autocommand that notifies when a file has been changed externally
	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = refresh_group,
		pattern = "*",
		callback = function()
			vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.INFO)
		end,
		desc = "Notify when a file is changed externally",
	})

	-- Set a shorter updatetime while Claude Code is open
	vim.api.nvim_create_autocmd("TermOpen", {
		group = refresh_group,
		pattern = "*",
		callback = function()
			local buf = vim.api.nvim_get_current_buf()
			local buf_name = vim.api.nvim_buf_get_name(buf)
			if buf_name:match("claude%-code$") then
				claude_module.saved_updatetime = vim.o.updatetime
				vim.o.updatetime = 100
			end
		end,
		desc = "Set shorter updatetime when Claude Code is open",
	})

	-- When Claude Code closes, restore normal updatetime
	vim.api.nvim_create_autocmd("TermClose", {
		group = refresh_group,
		pattern = "*",
		callback = function()
			local buf_name = vim.api.nvim_buf_get_name(0)
			if buf_name:match("claude%-code$") then
				vim.o.updatetime = claude_module.saved_updatetime
			end
		end,
		desc = "Restore normal updatetime when Claude Code is closed",
	})
end

-- Subcommand handlers
local subcommand_handlers = {}

-- Build Docker image
local function handle_build(claude_module, args)
	local cmd = docker.build_docker_image()
	log.info("Manual Docker image build initiated", true)
	vim.fn.system(cmd)
	if vim.v.shell_error == 0 then
		log.info("Docker image built successfully (manual)", true)
		-- Stop current container
		if claude_module.container_started then
			-- Close all docker buffer variants if they exist
			local docker_modes = { "claude-docker", "codex-docker", "opencode-docker" }
			for _, mode in ipairs(docker_modes) do
				local var_name = mode:gsub("-", "_")
				local buf_key = var_name .. "_buf"
				local job_key = var_name .. "_job_id"
				if claude_module[buf_key] then
					local buf, job = terminal.close_terminal_buffer(claude_module[buf_key], claude_module[job_key])
					claude_module[buf_key] = buf
					claude_module[job_key] = job
					-- Clear active pointers if this was the active buffer
					if claude_module.active_buf == buf then
						claude_module.active_buf = nil
						claude_module.active_job_id = nil
						claude_module.active_mode = "none"
					end
				end
			end
			docker.stop_container(claude_module.container_name)
			claude_module.container_started = false
			log.info("Stopped existing container")
		end
		-- Start new container
		docker.start_container_async(
			claude_module.container_name,
			claude_module.auto_build,
			claude_module.context_directories,
			function(success)
				if success then
					claude_module.container_started = true
				end
			end
		)
	else
		log.error("Failed to build Docker image (manual)", true)
	end
end
subcommand_handlers.build = handle_build

-- Restart container
local function handle_restart(claude_module, args)
	log.info("Manual container restart initiated", true)
	-- Stop current container
	if claude_module.container_started then
		-- Close all docker buffer variants if they exist
		local docker_modes = { "claude-docker", "codex-docker", "opencode-docker" }
		for _, mode in ipairs(docker_modes) do
			local var_name = mode:gsub("-", "_")
			local buf_key = var_name .. "_buf"
			local job_key = var_name .. "_job_id"
			if claude_module[buf_key] then
				local buf, job = terminal.close_terminal_buffer(claude_module[buf_key], claude_module[job_key])
				claude_module[buf_key] = buf
				claude_module[job_key] = job
				-- Clear active pointers if this was the active buffer
				if claude_module.active_buf == buf then
					claude_module.active_buf = nil
					claude_module.active_job_id = nil
					claude_module.active_mode = "none"
				end
			end
		end
		docker.stop_container(claude_module.container_name)
		claude_module.container_started = false
		log.info("Stopped existing container")
	end
	-- Start new container
	docker.start_container_async(
		claude_module.container_name,
		claude_module.auto_build,
		claude_module.context_directories,
		function(success)
			if success then
				claude_module.container_started = true
			end
		end
	)
end
subcommand_handlers.restart = handle_restart

-- Restart agent after context directory change (used by add-context and remove-context).
-- Handles both Docker and local/sandbox modes.
local function restart_agent_with_context(agent_module, action_desc)
	-- Docker mode: close all docker terminal buffers, then restart container
	-- Use container_started as the sole Docker indicator. active_mode is unreliable
	-- because hiding a terminal sets it to "none" while the container keeps running.
	if agent_module.container_started then
		vim.notify("Restarting container — " .. action_desc)
		-- Close all docker buffer variants (matches handle_restart cleanup logic)
		local docker_modes = { "claude-docker", "codex-docker", "opencode-docker" }
		for _, dmode in ipairs(docker_modes) do
			local var_name = dmode:gsub("-", "_")
			local buf_key = var_name .. "_buf"
			local job_key = var_name .. "_job_id"
			if agent_module[buf_key] then
				terminal.close_terminal_buffer(agent_module[buf_key], agent_module[job_key])
				agent_module[buf_key] = nil
				agent_module[job_key] = nil
			end
		end
		agent_module.active_buf = nil
		agent_module.active_job_id = nil
		agent_module.active_mode = "none"
		docker.stop_container(agent_module.container_name)
		agent_module.container_started = false
		docker.start_container_async(
			agent_module.container_name,
			agent_module.auto_build,
			agent_module.context_directories,
			function(success)
				if success then
					agent_module.container_started = true
				end
			end
		)
		return
	end

	-- Local/sandbox mode: restart via public helper
	local restarted = agent_module.restart_local_agent()
	if restarted then
		vim.notify("Restarting agent — " .. action_desc)
	else
		vim.notify(action_desc .. " — context will be applied when agent starts", vim.log.levels.INFO)
	end
end

-- Add context directory
local function handle_add_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :AiAgent add-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	if vim.fn.isdirectory(dir_path) == 0 then
		vim.notify("Directory does not exist: " .. dir_path, vim.log.levels.ERROR)
		return
	end
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h")
	if claude_module.context_directories[abs_path] then
		vim.notify("Context already added: " .. abs_path, vim.log.levels.INFO)
		return
	end
	claude_module.context_directories[abs_path] = true
	log.info("Added context directory: " .. abs_path)
	restart_agent_with_context(claude_module, "added context: " .. abs_path)
end
subcommand_handlers["add-context"] = handle_add_context

-- Remove context directory
local function handle_remove_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :AiAgent remove-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h")
	if not claude_module.context_directories[abs_path] then
		vim.notify("Context not found: " .. abs_path, vim.log.levels.WARN)
		return
	end
	claude_module.context_directories[abs_path] = nil
	log.info("Removed context directory: " .. abs_path)
	restart_agent_with_context(claude_module, "removed context: " .. abs_path)
end
subcommand_handlers["remove-context"] = handle_remove_context

-- List context directories
local function handle_list_contexts(claude_module, args)
	if vim.tbl_isempty(claude_module.context_directories) then
		vim.notify("No context directories mounted", vim.log.levels.INFO)
		return
	end
	local lines = { "Context directories mounted in container:" }
	local i = 1
	for source_path, _ in pairs(claude_module.context_directories) do
		local dir_name = vim.fn.fnamemodify(source_path, ":t")
		-- Check for duplicates to show actual mount name
		local mount_name = dir_name
		local has_duplicate = false
		for other_path, _ in pairs(claude_module.context_directories) do
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
end
subcommand_handlers["list-contexts"] = handle_list_contexts

-- Clear scrollback for active buffer
local function handle_clear_scrollback(claude_module, args)
	-- Clear scrollback for the active buffer
	local buf = claude_module.active_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		log.warn("No active buffer to clear scrollback")
		return
	end

	buffer_config.clear_scrollback(buf)
end
subcommand_handlers["clear-scrollback"] = handle_clear_scrollback

-- Toggle follow mode for active buffer
local function handle_toggle_follow(claude_module, args)
	-- Toggle follow mode for active buffer
	local buf = claude_module.active_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		log.warn("No active buffer to toggle follow mode")
		return
	end

	buffer_config.toggle_follow_mode(buf)
end
subcommand_handlers["toggle-follow"] = handle_toggle_follow

-- Open shell in container
local function handle_shell(claude_module, args)
	if not docker.is_container_running(claude_module.container_name) then
		vim.notify("Claude container is not running. Start it first.", vim.log.levels.ERROR)
		return
	end
	log.info("Opening shell in Claude container")
	local found, _ = terminal.open_or_reuse_terminal_buffer(claude_module.shell_buf, "vsplit")
	if not found then
		-- Create new shell terminal
		terminal.open_window("vsplit")
		claude_module.shell_buf = vim.api.nvim_get_current_buf()
		-- Start shell in container
		claude_module.shell_job_id =
			vim.fn.termopen("docker exec -it " .. claude_module.container_name .. " /bin/bash", {
				on_exit = function(_, exit_code)
					log.debug("Container shell exited with code: " .. exit_code)
					claude_module.shell_buf = nil
					claude_module.shell_job_id = nil
				end,
			})
		vim.bo[claude_module.shell_buf].bufhidden = "hide"
		vim.bo[claude_module.shell_buf].filetype = "ClaudeShell"
		vim.cmd("startinsert")
	end
end
subcommand_handlers.shell = handle_shell

-- Show log file
local function handle_show_log(claude_module, args)
	local log_file = log.get_log_file()
	if vim.fn.filereadable(log_file) == 1 then
		vim.cmd("tabnew " .. vim.fn.fnameescape(log_file))
		vim.bo.filetype = "log"
		-- Jump to end of file to see latest entries
		vim.cmd("normal! G")
	else
		vim.notify("Claude log file not found: " .. log_file, vim.log.levels.WARN)
	end
end
subcommand_handlers["show-log"] = handle_show_log

-- Show container logs
local function handle_container_logs(claude_module, args)
	if not docker.is_container_running(claude_module.container_name) then
		vim.notify("Claude container is not running. Start it first.", vim.log.levels.ERROR)
		return
	end
	log.info("Opening Claude container logs")
	local found, _ = terminal.open_or_reuse_terminal_buffer(claude_module.logs_buf, "vsplit")
	if not found then
		-- Create new logs terminal
		terminal.open_window("vsplit")
		claude_module.logs_buf = vim.api.nvim_get_current_buf()
		-- Show logs from container (check claude-cli-nodejs cache directory)
		claude_module.logs_job_id = vim.fn.termopen(
			"docker exec -it "
				.. claude_module.container_name
				.. ' /bin/bash -c \'for dir in /home/node/.cache/claude-cli-nodejs/-workspace /home/node/.cache/claude-cli-nodejs; do if [ -d "$dir" ]; then find "$dir" -name "*.log" -type f -exec echo "=== {} ===" \\; -exec cat {} \\; -exec echo "" \\; 2>/dev/null; fi; done || echo "No log files found"\'',
			{
				on_exit = function(_, exit_code)
					log.debug("Container logs command exited with code: " .. exit_code)
					claude_module.logs_buf = nil
					claude_module.logs_job_id = nil
				end,
			}
		)
		vim.bo[claude_module.logs_buf].bufhidden = "hide"
		vim.bo[claude_module.logs_buf].filetype = "log"
		vim.cmd("startinsert")
	end
end
subcommand_handlers["container-logs"] = handle_container_logs

-- Set or show log level
local function handle_log_level(claude_module, args)
	local level_map = {
		TRACE = vim.log.levels.TRACE,
		DEBUG = vim.log.levels.DEBUG,
		INFO = vim.log.levels.INFO,
		WARN = vim.log.levels.WARN,
		ERROR = vim.log.levels.ERROR,
		OFF = vim.log.levels.OFF,
	}
	local level_arg = args[1]
	if not level_arg then
		local current = log.get_level_name()
		vim.notify("Current Claude log level: " .. current)
		return
	end
	local new_level = level_map[string.upper(level_arg)]
	if new_level then
		log.set_level(new_level)
		vim.notify("Claude log level set to: " .. string.upper(level_arg))
		log.info("Log level changed to: " .. string.upper(level_arg))
	else
		vim.notify("Invalid log level. Use: TRACE, DEBUG, INFO, WARN, ERROR, OFF", vim.log.levels.ERROR)
	end
end
subcommand_handlers["log-level"] = handle_log_level

-- Check firewall status
local function handle_check_firewall(claude_module, args)
	if not docker.is_container_running(claude_module.container_name) then
		vim.notify("Claude container is not running", vim.log.levels.ERROR)
		return
	end
	log.info("Checking firewall status...")
	-- Check if policies are set to DROP
	local policy_check = docker.check_firewall_status(claude_module.container_name)
	if policy_check then
		vim.notify("✓ Firewall policies are set to DROP (secure)", vim.log.levels.INFO)
	else
		vim.notify("✗ Firewall policies are NOT set to DROP (insecure)", vim.log.levels.WARN)
	end
	-- Run detailed check
	local check_cmd = "docker exec "
		.. claude_module.container_name
		.. [[ bash -c "echo '=== INPUT Chain ==='; sudo iptables -L INPUT -n -v | head -5; echo; echo '=== OUTPUT Chain ==='; sudo iptables -L OUTPUT -n -v | head -5; echo; echo '=== Allowed IPs ==='; sudo ipset list allowed_ips 2>/dev/null | head -10 || echo 'No ipset found'"]]
	local handle = io.popen(check_cmd .. " 2>&1")
	if handle then
		local result = handle:read("*a")
		handle:close()
		vim.notify("Firewall Status:\n" .. result, vim.log.levels.INFO)
	else
		vim.notify("Failed to check firewall status", vim.log.levels.ERROR)
	end
end
subcommand_handlers["check-firewall"] = handle_check_firewall

-- Main command handler for AiAgent
local function handle_aiagent_command(args, agent_module)
	local subcommand = args.fargs[1]
	local rest_args = vim.list_slice(args.fargs, 2)

	if not subcommand then
		vim.notify("Usage: :AiAgent <subcommand> [args]", vim.log.levels.INFO)
		vim.notify(
			"Available subcommands: build, restart, add-context, remove-context, list-contexts, shell, show-log, container-logs, log-level, check-firewall, clear-scrollback, toggle-follow",
			vim.log.levels.INFO
		)
		return
	end

	-- Look up and execute the subcommand handler
	local handler = subcommand_handlers[subcommand]
	if handler then
		handler(agent_module, rest_args)
	else
		vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
		vim.notify(
			"Available subcommands: build, restart, add-context, remove-context, list-contexts, shell, show-log, container-logs, log-level, check-firewall, clear-scrollback, toggle-follow",
			vim.log.levels.INFO
		)
	end
end

-- Setup user commands
function M.setup_user_commands(agent_module)
	-- Main AiAgent command with subcommands
	vim.api.nvim_create_user_command("AiAgent", function(args)
		handle_aiagent_command(args, agent_module)
	end, {
		nargs = "+",
		complete = function(arg_lead, cmd_line, cursor_pos)
			local parts = vim.split(cmd_line, "%s+")
			local num_args = #parts - 1 -- Subtract 1 for the command itself

			-- If we're completing the first argument (subcommand)
			if num_args == 0 or (num_args == 1 and not cmd_line:match("%s$")) then
				local subcommands = {
					"build",
					"restart",
					"add-context",
					"remove-context",
					"list-contexts",
					"shell",
					"show-log",
					"container-logs",
					"log-level",
					"check-firewall",
					"clear-scrollback",
					"toggle-follow",
				}
				return vim.tbl_filter(function(cmd)
					return cmd:find("^" .. arg_lead)
				end, subcommands)
			end

			-- Get the subcommand
			local subcommand = parts[2]

			-- Provide completions based on subcommand
			if subcommand == "add-context" then
				-- Directory completion
				return vim.fn.getcompletion(arg_lead, "dir")
			elseif subcommand == "remove-context" then
				-- Complete from existing contexts
				local contexts = {}
				for path, _ in pairs(agent_module.context_directories) do
					table.insert(contexts, path)
				end
				return vim.tbl_filter(function(path)
					return path:find("^" .. arg_lead)
				end, contexts)
			elseif subcommand == "log-level" then
				local levels = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
				return vim.tbl_filter(function(level)
					return level:find("^" .. string.upper(arg_lead))
				end, levels)
			end

			return {}
		end,
		desc = "AI Agent management commands",
	})
end

return M
