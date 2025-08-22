local M = {}

local docker = require("tw.claude.docker")
local terminal = require("tw.claude.terminal")
local log = require("tw.log")

-- Timer for checking file changes
local refresh_timer = nil

-- Setup autocmds for file refresh and other events
function M.setup_autocmds(claude_module)
	local group = vim.api.nvim_create_augroup("Claude", { clear = true })

	-- Start container on Vim startup if in docker mode (async)
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = function()
			if claude_module.docker_mode then
				log.info("VimEnter triggered, Docker mode enabled")
				vim.defer_fn(function()
					log.info("Starting async container startup after delay")
					docker.start_container_async(
						claude_module.container_name,
						claude_module.auto_build,
						claude_module.context_directories,
						function(success, status)
							if success then
								claude_module.container_started = true
							else
								claude_module.docker_mode = false
								claude_module.container_started = false
							end
						end
					)
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
			claude_module.cleanup()
			if claude_module.docker_mode and claude_module.container_started then
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

	-- Set nowrap for Claude buffer windows, which makes code changes look better
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			-- Check if this is the Claude buffer
			if claude_module.claude_buf and args.buf == claude_module.claude_buf then
				-- Set nowrap for the window displaying this buffer
				vim.wo[0].wrap = false
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
	refresh_timer = vim.loop.new_timer()
	if refresh_timer then
		refresh_timer:start(
			0,
			1000, -- milliseconds
			vim.schedule_wrap(function()
				-- Only check time if there's an active Claude Code terminal
				local bufnr = claude_module.claude_buf
				if bufnr and vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) > 0 then
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

-- Toggle between Docker and native mode
local function handle_toggle(claude_module, args)
	if claude_module.docker_mode then
		-- Switching from docker to native mode
		if claude_module.container_started then
			local buf, job = terminal.close_terminal_buffer(claude_module.claude_buf, claude_module.claude_job_id)
			claude_module.claude_buf = buf
			claude_module.claude_job_id = job
			docker.stop_container(claude_module.container_name)
			claude_module.container_started = false
		end
		claude_module.docker_mode = false
		vim.notify("Claude Docker mode: disabled (container " .. claude_module.container_name .. ")")
	else
		-- Switching from native to docker mode
		claude_module.docker_mode = true
		vim.notify("Claude Docker mode: enabled - starting container " .. claude_module.container_name .. "...")
		-- Start container asynchronously
		docker.start_container_async(
			claude_module.container_name,
			claude_module.auto_build,
			claude_module.context_directories,
			function(success)
				if success then
					claude_module.container_started = true
				else
					claude_module.docker_mode = false
				end
			end
		)
	end
end
subcommand_handlers.toggle = handle_toggle

-- Build Docker image
local function handle_build(claude_module, args)
	local cmd = docker.build_docker_image()
	log.info("Manual Docker image build initiated", true)
	vim.fn.system(cmd)
	if vim.v.shell_error == 0 then
		log.info("Docker image built successfully (manual)", true)
		-- Stop current container
		if claude_module.docker_mode and claude_module.container_started then
			local buf, job = terminal.close_terminal_buffer(claude_module.claude_buf, claude_module.claude_job_id)
			claude_module.claude_buf = buf
			claude_module.claude_job_id = job
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
	if not claude_module.docker_mode then
		vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
		return
	end
	log.info("Manual container restart initiated", true)
	-- Stop current container
	if claude_module.container_started then
		local buf, job = terminal.close_terminal_buffer(claude_module.claude_buf, claude_module.claude_job_id)
		claude_module.claude_buf = buf
		claude_module.claude_job_id = job
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

-- Add context directory
local function handle_add_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :ClaudeDocker add-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	-- Validate directory exists
	if vim.fn.isdirectory(dir_path) == 0 then
		vim.notify("Directory does not exist: " .. dir_path, vim.log.levels.ERROR)
		return
	end
	-- Get absolute path
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h") -- :h removes trailing slash
	-- Check if already added
	if claude_module.context_directories[abs_path] then
		vim.notify("Context already added: " .. abs_path, vim.log.levels.INFO)
		return
	end
	-- Add to context directories
	claude_module.context_directories[abs_path] = true
	log.info("Added context directory: " .. abs_path)
	-- Restart container with new mounts
	if claude_module.docker_mode and claude_module.container_started then
		vim.notify("Restarting container with new context: " .. abs_path)
		local buf, job = terminal.close_terminal_buffer(claude_module.claude_buf, claude_module.claude_job_id)
		claude_module.claude_buf = buf
		claude_module.claude_job_id = job
		docker.stop_container(claude_module.container_name)
		claude_module.container_started = false
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
		vim.notify("Context will be mounted when container starts: " .. abs_path)
	end
end
subcommand_handlers["add-context"] = handle_add_context

-- Remove context directory
local function handle_remove_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :ClaudeDocker remove-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h")
	if not claude_module.context_directories[abs_path] then
		vim.notify("Context not found: " .. abs_path, vim.log.levels.WARN)
		return
	end
	-- Remove from context directories
	claude_module.context_directories[abs_path] = nil
	log.info("Removed context directory: " .. abs_path)
	-- Restart container if running
	if claude_module.docker_mode and claude_module.container_started then
		vim.notify("Restarting container without context: " .. abs_path)
		local buf, job = terminal.close_terminal_buffer(claude_module.claude_buf, claude_module.claude_job_id)
		claude_module.claude_buf = buf
		claude_module.claude_job_id = job
		docker.stop_container(claude_module.container_name)
		claude_module.container_started = false
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
		vim.notify("Context removed: " .. abs_path)
	end
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

-- Open shell in container
local function handle_shell(claude_module, args)
	if not claude_module.docker_mode then
		vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
		return
	end
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
	if not claude_module.docker_mode then
		vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
		return
	end
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
	if not claude_module.docker_mode then
		vim.notify("Docker mode is not enabled", vim.log.levels.WARN)
		return
	end
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

-- Main command handler for ClaudeDocker
local function handle_claude_docker_command(args, claude_module)
	local subcommand = args.fargs[1]
	local rest_args = vim.list_slice(args.fargs, 2)

	if not subcommand then
		vim.notify("Usage: :ClaudeDocker <subcommand> [args]", vim.log.levels.INFO)
		vim.notify(
			"Available subcommands: toggle, build, restart, add-context, remove-context, list-contexts, shell, show-log, container-logs, log-level, check-firewall",
			vim.log.levels.INFO
		)
		return
	end

	-- Look up and execute the subcommand handler
	local handler = subcommand_handlers[subcommand]
	if handler then
		handler(claude_module, rest_args)
	else
		vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
		vim.notify(
			"Available subcommands: toggle, build, restart, add-context, remove-context, list-contexts, shell, show-log, container-logs, log-level, check-firewall",
			vim.log.levels.INFO
		)
	end
end

-- Setup user commands
function M.setup_user_commands(claude_module)
	-- Main ClaudeDocker command with subcommands
	vim.api.nvim_create_user_command("ClaudeDocker", function(args)
		handle_claude_docker_command(args, claude_module)
	end, {
		nargs = "+",
		complete = function(arg_lead, cmd_line, cursor_pos)
			local parts = vim.split(cmd_line, "%s+")
			local num_args = #parts - 1 -- Subtract 1 for the command itself

			-- If we're completing the first argument (subcommand)
			if num_args == 0 or (num_args == 1 and not cmd_line:match("%s$")) then
				local subcommands = {
					"toggle",
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
				for path, _ in pairs(claude_module.context_directories) do
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
		desc = "Claude Docker management commands",
	})
end

return M
