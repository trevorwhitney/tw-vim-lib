local M = {}

local claude = require("tw.agent.claude")
local docker = require("tw.agent.docker")
local terminal = require("tw.agent.terminal")
local util = require("tw.agent.util")
local log = require("tw.log")
local commands = require("tw.agent.commands")
local buffer_config = require("tw.agent.buffer-config")
local default_args = {}

-- Expose log module globally for claude.lua to use
_G.claude_log = log
-- Separate buffers for each mode (local and docker variants)
M.claude_buf = nil
M.claude_job_id = nil
M.claude_docker_buf = nil
M.claude_docker_job_id = nil
M.codex_buf = nil
M.codex_job_id = nil
M.codex_docker_buf = nil
M.codex_docker_job_id = nil
M.opencode_buf = nil
M.opencode_job_id = nil
M.opencode_docker_buf = nil
M.opencode_docker_job_id = nil
M.active_mode = "opencode" -- Track which mode is currently visible: "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker", or "none"

-- Active buffer/job_id points to the currently visible buffer
M.active_buf = nil
M.active_job_id = nil

M.saved_updatetime = nil
M.shell_buf = nil
M.shell_job_id = nil
M.logs_buf = nil
M.logs_job_id = nil

-- Workmux fullscreen state: when true, opencode occupies the full viewport
-- and will revert to a vsplit when a non-terminal buffer is opened.
M.workmux_fullscreen = false

-- Container configuration
M.auto_build = true -- Auto-build image if missing
M.container_started = false -- Track if we started the container
M.container_name = string.format("claude-code-nvim-%d-%d", vim.fn.getpid(), os.time()) -- More unique container name
-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount at /context/*
M.mount_info = nil -- Cached workspace mount info from last container start

-- Buffer configuration
M.buffer_config = {
	scrollback = 5000,
	follow_output = true,
	prevent_resize_scroll = true,
}

-- Helper function to get buffer and job_id for a given mode
local function get_mode_vars(mode)
	local var_name = mode:gsub("-", "_") -- Convert "claude-docker" to "claude_docker"
	return {
		buf_key = var_name .. "_buf",
		job_key = var_name .. "_job_id",
	}
end

-- Helper function to parse mode into command and location
local function parse_mode(mode)
	local is_docker = mode:match("-docker$")
	local command_name = mode:gsub("-docker$", "") -- Remove -docker suffix if present
	return command_name, is_docker ~= nil
end

-- Find the plugin installation path
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/agent/init%.lua$")
	return plugin_root
end

local function OnExit(mode)
	return function(job_id, exit_code, event_type)
		vim.schedule(function()
			local vars = get_mode_vars(mode)
			local buf = M[vars.buf_key]

			if buf and vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modifiable = true
				local message
				if exit_code == 0 then
					message = "Process completed successfully."
				else
					message = "Process exited with code: " .. exit_code
				end
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", message })
				vim.bo[buf].modifiable = false
			end

			-- Clear buffer and job state when process exits
			M[vars.buf_key] = nil
			M[vars.job_key] = nil

			-- Update active pointers if this was the active buffer
			if M.active_buf == buf then
				M.active_buf = nil
				M.active_job_id = nil
				M.active_mode = "none"
			end
		end)
	end
end

local function close_buffer_windows(buf)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	while true do
		local closed = false
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_win_close(win, false)
				closed = true
				break
			end
		end
		if not closed then
			break
		end
	end
end

local function close_other_mode_buffers(active_mode)
	local seen = {}
	local function enqueue(buf)
		if buf and vim.api.nvim_buf_is_valid(buf) and not seen[buf] then
			seen[buf] = true
			close_buffer_windows(buf)
		end
	end

	local all_modes = { "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker" }
	for _, mode in ipairs(all_modes) do
		if mode ~= active_mode then
			local vars = get_mode_vars(mode)
			enqueue(M[vars.buf_key])
		end
	end
end

local function start_new_agent_job(args, window_type, mode)
	mode = mode or "claude"
	log.info("Attempting to start new job in " .. mode .. " mode")

	-- Parse mode to get command name and location
	local command_name, is_docker = parse_mode(mode)
	log.debug("Command: " .. command_name .. ", Docker: " .. tostring(is_docker))

	-- Create a copy of args to avoid mutating the original (especially default_args)
	args = args and vim.deepcopy(args) or {}

	-- For opencode, always add the project root path
	if command_name == "opencode" then
		log.debug("Processing opencode command")
		local git_root = util.get_git_root()
		log.debug("Git root: " .. tostring(git_root))
		if git_root then
			log.debug("Initial args count: " .. #args)
			local project_path

			if is_docker then
				-- Determine project path based on mount strategy
				local mi = docker.workspace_mount_info()
				if mi.is_workspace_mode then
					-- Git root is accessible under the workspace mount — translate path directly
					local host_ws = mi.host_workspace
					local is_git_root_under_ws = git_root == host_ws or git_root:sub(1, #host_ws + 1) == host_ws .. "/"
					if is_git_root_under_ws then
						local relative = git_root:sub(#host_ws + 1) -- includes leading "/"
						project_path = mi.container_workspace .. relative
					else
						-- Git root outside workspace — fall back to context dir mount
						if not M.context_directories[git_root] then
							M.context_directories[git_root] = true
							log.info("Auto-added git root to context directories: " .. git_root)
						end
						local dir_name = vim.fn.fnamemodify(git_root, ":t")
						project_path = "/context/" .. dir_name
					end
				else
					-- Fallback mode: git root IS the mounted CWD
					project_path = mi.container_workspace
				end
				log.debug("Docker project path: " .. project_path)
			else
				-- In local mode, use the host git root path
				project_path = git_root
				log.debug("Local project path: " .. project_path)
			end

			-- Prepend project path to args if not already present
			if #args == 0 or args[1] ~= project_path then
				table.insert(args, 1, project_path)
				log.debug("Prepended project path to args")
			end
			log.debug("Final args count: " .. #args)
			if #args > 0 then
				log.debug("Args: " .. vim.inspect(args))
			end
		end
	end

	-- Launch the command
	local command
	local buf, job_id

	if is_docker then
		log.debug(mode .. " mode enabled, checking container status")
		-- Check if container is running, if not try to start it
		local is_running, container_id, status = docker.is_container_running(M.container_name)
		log.debug("Container running check result: " .. tostring(is_running))
		log.debug("Container ID: " .. (container_id or "none"))
		log.debug("Container status: " .. (status or "unknown"))
		log.debug("Container started flag: " .. tostring(M.container_started))

		if not is_running then
			-- Helper function to start container and wait for completion
			local function wait_for_container_start(action_name)
				local success_flag = false
				local captured_mount_info = nil
				docker.start_container_async(
					M.container_name,
					M.auto_build,
					M.context_directories,
					function(success, status, mount_info)
						if success then
							M.container_started = true
							captured_mount_info = mount_info
							success_flag = true
						else
							log.error(
								"Failed to " .. action_name .. " container: " .. (status or "Unknown error"),
								true
							)
							M.container_started = false
							success_flag = false
						end
					end
				)

				-- Wait for container with timeout
				local timeout = 30000 -- 30 seconds
				local check_interval = 500 -- 0.5 seconds
				local elapsed = 0
				while elapsed < timeout do
					vim.wait(check_interval)
					elapsed = elapsed + check_interval
					if success_flag then
						break
					end
					if not success_flag and elapsed >= timeout then
						log.error("Container " .. action_name .. " timed out", true)
						M.container_started = false
						return false
					end
				end

				if not success_flag then
					log.error("Container " .. action_name .. " failed", true)
					M.container_started = false
					return false
				end
				M.mount_info = captured_mount_info
				return true
			end
			if M.container_started then
				-- Container was started but isn't running - restart it
				log.warn("Container was started but is not running, attempting restart", true)
				docker.ensure_container_stopped(M.container_name)
				if not wait_for_container_start("restart") then
					return
				end
			else
				-- Container not started - start it on-demand
				log.info("Container not running, starting on-demand", true)
				if not wait_for_container_start("start") then
					return
				end
			end
		end

		local cmd_args = ""
		if args and #args > 0 then
			cmd_args = table.concat(args, " ")
		end
		-- Use mount info for working directory (may have been set during container start,
		-- or compute fresh if container was already running)
		local working_dir
		if M.mount_info then
			working_dir = M.mount_info.container_cwd
		else
			working_dir = docker.workspace_mount_info().container_cwd
		end
		command = docker.attach_to_container(M.container_name, cmd_args, command_name, working_dir)
		log.debug("Using docker attach command: " .. command)
	else
		log.debug("Local mode enabled for " .. command_name)
		local final_args = vim.tbl_extend("force", {}, default_args)
		if args and #args > 0 then
			log.debug("Extending final_args with " .. #args .. " args")
			vim.list_extend(final_args, args)
		end
		log.debug("Final args before command: " .. vim.inspect(final_args))
		command = claude.command(final_args, command_name, M.context_directories)
		if not command then
			log.error("Failed to build command for " .. command_name, true)
			return
		end
		log.debug("Using native command: " .. command)
	end

	log.info("Starting " .. command_name .. " with command: " .. command)

	-- Hide the other mode's buffer if it's visible before opening new window
	close_other_mode_buffers(mode)

	terminal.open_window(window_type)
	buf = vim.api.nvim_get_current_buf()
	job_id = vim.fn.termopen(command, {
		on_exit = OnExit(mode),
		-- TODO: make this configurable
		env = {
			BUILD_IN_CONTAINER = "false",
			-- Unset TMUX/STY so child processes emit plain OSC 52 clipboard
			-- sequences instead of wrapping them in tmux DCS passthrough.
			-- Neovim's terminal emulator handles plain OSC 52 natively but
			-- cannot parse tmux DCS wrappers, causing raw base64 to leak
			-- onto the display.
			TMUX = "",
			STY = "",
		},
	})
	vim.bo[buf].bufhidden = "hide"

	-- Configure the buffer with scrollback and resize handling
	buffer_config.setup_buffer(buf, M.buffer_config)

	-- Store buffer and job based on mode
	local vars = get_mode_vars(mode)
	M[vars.buf_key] = buf
	M[vars.job_key] = job_id

	-- Update active mode and pointers
	M.active_mode = mode
	M.active_buf = buf
	M.active_job_id = job_id

	vim.defer_fn(function()
		vim.cmd("startinsert")
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
	-- Send to the active job
	local job_id = M.active_job_id
	if job_id then
		vim.fn.chansend(job_id, text)
	else
		log.warn("No active job to send to")
	end
end

local function confirmOpenAndDo(callback, args, window_type)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Determine which buffer to use (default to claude local if none active)
	local active_buf = M.active_buf
	if not active_buf or not vim.api.nvim_buf_is_valid(active_buf) then
		-- No active buffer, use active_mode (or fall back to claude)
		M.Open(M.active_mode, args, window_type)

		-- Wait a bit for the chat to initialize
		vim.defer_fn(function()
			if callback then
				callback()
			end
			-- Focus active buffer and enter insert mode
			if M.active_buf and vim.api.nvim_buf_is_valid(M.active_buf) then
				local windows = vim.api.nvim_list_wins()
				for _, win in ipairs(windows) do
					if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.active_buf then
						vim.api.nvim_set_current_win(win)
						vim.cmd("startinsert")
						break
					end
				end
			end
		end, 2500)
	else
		-- Buffer exists, make sure it's visible
		local windows = vim.api.nvim_list_wins()
		local is_visible = false
		local claude_win = nil

		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == active_buf then
				-- Buffer is visible
				is_visible = true
				claude_win = win
				break
			end
		end

		-- If buffer exists but is not visible, show it in window_type
		if not is_visible then
			terminal.open_buffer_in_new_window(window_type, active_buf)
			-- Find the new window
			windows = vim.api.nvim_list_wins()
			for _, win in ipairs(windows) do
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == active_buf then
					claude_win = win
					break
				end
			end
		end

		if callback then
			callback()
		end

		-- Focus the Claude window and enter insert mode
		if claude_win then
			vim.api.nvim_set_current_win(claude_win)
			vim.cmd("startinsert")
		end
	end
end

function M.Open(mode, args, window_type)
	mode = mode or "claude" -- Default to claude local mode
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Get the appropriate buffer and job for the mode
	local vars = get_mode_vars(mode)
	local buf = M[vars.buf_key]
	local job_id = M[vars.job_key]

	-- Check if buffer exists, is valid, AND the job is still running
	local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

	if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
		-- First, hide the other mode's buffer if it's visible
		close_other_mode_buffers(mode)
		terminal.open_buffer_in_new_window(window_type, buf)
		-- Update active mode and pointers
		M.active_mode = mode
		M.active_buf = buf
		M.active_job_id = job_id
	else
		-- Clean up dead buffer if needed
		if buf and not job_is_running then
			local cleaned_buf, cleaned_job = terminal.close_terminal_buffer(buf, job_id)
			M[vars.buf_key] = cleaned_buf
			M[vars.job_key] = cleaned_job
		end
		start_new_agent_job(args, window_type, mode)
	end
end

function M.Toggle(mode, args, window_type)
	mode = mode or "claude" -- Default to claude local if not specified
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Get the appropriate buffer and job based on mode
	local vars = get_mode_vars(mode)
	local buf = M[vars.buf_key]
	local job_id = M[vars.job_key]

	-- Check if buffer exists, is valid, AND the job is still running
	local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

	if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
		-- Buffer exists and job is running - toggle visibility
		local windows = vim.api.nvim_list_wins()
		local is_visible = false

		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				-- Buffer is visible, hide it by closing the window
				vim.api.nvim_win_close(win, false)
				is_visible = true
				-- Clear active mode when hiding
				if M.active_buf == buf then
					M.active_mode = "none"
					M.active_buf = nil
					M.active_job_id = nil
				end
				break
			end
		end

		-- If buffer exists but is not visible, show it in window_type
		if not is_visible then
			-- First, hide the other mode's buffer if it's visible
			close_other_mode_buffers(mode)
			terminal.open_buffer_in_new_window(window_type, buf)
			-- Update active mode and pointers
			M.active_mode = mode
			M.active_buf = buf
			M.active_job_id = job_id
		end
	else
		-- Buffer doesn't exist or job is dead, clean up and create new
		if buf and not job_is_running then
			local cleaned_buf, cleaned_job = terminal.close_terminal_buffer(buf, job_id)
			M[vars.buf_key] = cleaned_buf
			M[vars.job_key] = cleaned_job
		end
		M.Open(mode, args, window_type)
	end
end

-- Helper function to hide all agent buffers
function M.hide_all_agent_buffers()
	local windows = vim.api.nvim_list_wins()
	local all_modes = { "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker" }
	for _, win in ipairs(windows) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			for _, mode in ipairs(all_modes) do
				local vars = get_mode_vars(mode)
				if buf == M[vars.buf_key] then
					vim.api.nvim_win_close(win, false)
					break
				end
			end
		end
	end
end

-- Backwards compatibility alias
M.hide_all_claude_buffers = M.hide_all_agent_buffers

local function submit()
	vim.defer_fn(function()
		local job_id = M.active_job_id
		if job_id then
			vim.fn.chansend(job_id, "\r")
		else
			log.warn("No active job to submit to")
		end
	end, 500)
end

function M.SendCommand(args, submit_after)
	submit_after = submit_after or false
	confirmOpenAndDo(function()
		vim.fn.chansend(M.active_job_id, "!")
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

function M.SendSelection()
	local Path = require("plenary.path")
	-- Resolve file path FIRST — bail before any side effects if unresolvable
	local filename, repo_root = util.resolve_file_path()
	if not filename then
		vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
		return
	end

	local git_root = repo_root or util.get_git_root()
	local rel_path = Path:new(filename):make_relative(git_root)

	-- Yank sets the '< and '> marks reliably
	vim.cmd('normal! "sy')

	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")

	-- Exit visual mode before opening agent
	vim.cmd("normal! \027") -- \027 is escape key

	-- Format: @filename:start-end
	local reference
	if start_line == end_line then
		reference = "@" .. rel_path .. ":" .. start_line .. " "
	else
		reference = "@" .. rel_path .. ":" .. start_line .. "-" .. end_line .. " "
	end

	confirmOpenAndDo(function()
		M.SendText({ reference })
	end)
end

function M.SendSymbol()
	local Path = require("plenary.path")
	local filename, repo_root = util.resolve_file_path()
	if not filename then
		vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
		return
	end

	local git_root = repo_root or util.get_git_root()
	local rel_path = Path:new(filename):make_relative(git_root)
	local word = vim.fn.expand("<cword>")
	local line_num = vim.fn.line(".")
	confirmOpenAndDo(function()
		M.SendText({
			word .. " @" .. rel_path .. ":" .. line_num .. " ",
		})
	end)
end

function M.SendFile()
	local Path = require("plenary.path")
	local filename, repo_root = util.resolve_file_path()
	if not filename then
		vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
		return
	end

	local git_root = repo_root or util.get_git_root()
	local rel_path = Path:new(filename):make_relative(git_root)
	confirmOpenAndDo(function()
		M.SendText({
			"@" .. rel_path .. " ",
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
			"Load the files then wait for my instructions.",
		}, true)
	end)
end

function M.StartClaude()
	confirmOpenAndDo(nil)
end

local function configureClaudeKeymap()
	local keymap = {
		{ "<leader>c", group = "AI Agents", nowait = true, remap = false },
		{
			mode = { "n", "v" },
			{
				"<leader>cl",
				function()
					require("tw.agent").Toggle("claude")
				end,
				desc = "Toggle Claude Local",
			},
			{
				"<leader>cL",
				function()
					require("tw.agent").Toggle("claude-docker")
				end,
				desc = "Toggle Claude Docker",
			},
			{
				"<leader>cx",
				function()
					require("tw.agent").Toggle("codex")
				end,
				desc = "Toggle Codex Local",
			},
			{
				"<leader>cX",
				function()
					require("tw.agent").Toggle("codex-docker")
				end,
				desc = "Toggle Codex Docker",
			},
			{
				"<leader>co",
				function()
					require("tw.agent").Toggle("opencode")
				end,
				desc = "Toggle OpenCode Local",
			},
			{
				"<leader>cO",
				function()
					require("tw.agent").Toggle("opencode-docker")
				end,
				desc = "Toggle OpenCode Docker",
			},
		},
		{
			mode = { "n" },
			{
				"<leader>tc",
				":w<cr> :TestNearest -strategy=claude<cr>",
				desc = "Test Nearest (claude)",
				nowait = false,
				remap = false,
			},
			{
				"<leader>c*",
				function()
					require("tw.agent").SendSymbol()
				end,
				desc = "Send Current Word to AI Agent",
				nowait = false,
				remap = false,
			},
			{
				"<leader>cf",
				function()
					require("tw.agent").SendFile()
				end,
				desc = "Send File to AI Agent",
				nowait = false,
				remap = false,
			},

			{
				"<leader>cb",
				function()
					require("tw.agent").SendOpenBuffers()
				end,
				desc = "Send Open Buffers to AI Agent",
				nowait = false,
				remap = false,
			},
		},
		{
			mode = { "v" },
			{
				"<leader>c*",
				function()
					require("tw.agent").SendSelection()
				end,
				desc = "Send Selection to AI Agent",
				nowait = false,
				remap = false,
			},
		},
	}

	local wk = require("which-key")
	wk.add(keymap)
end

function M.cleanup()
	-- Clean up all mode buffers and jobs
	local all_modes = { "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker" }
	for _, mode in ipairs(all_modes) do
		local vars = get_mode_vars(mode)
		local job_id = M[vars.job_key]
		local buf = M[vars.buf_key]

		if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			vim.fn.jobstop(job_id)
			M[vars.job_key] = nil
		end
		if buf then
			buffer_config.cleanup(buf)
		end
	end

	-- Clean up active pointers
	M.active_job_id = nil
	M.active_buf = nil

	if M.shell_job_id and vim.fn.jobwait({ M.shell_job_id }, 0)[1] == -1 then
		vim.fn.jobstop(M.shell_job_id)
		M.shell_job_id = nil
	end
	if M.logs_job_id and vim.fn.jobwait({ M.logs_job_id }, 0)[1] == -1 then
		vim.fn.jobstop(M.logs_job_id)
		M.logs_job_id = nil
	end
	if M._refresh_timer then
		M._refresh_timer:stop()
		M._refresh_timer:close()
		M._refresh_timer = nil
	end
end

-- Get status for statusline integration
function M.get_status()
	local container_running = false
	local container_name = nil

	-- Check container status
	if M.container_started then
		local is_running = docker.is_container_running(M.container_name)
		if is_running then
			container_running = true
			container_name = M.container_name
		end
	end

	return {
		mode = M.active_mode,
		container_running = container_running,
		container_name = container_name,
	}
end

--- Persist a worktree description to worktrees.json in the parent directory.
--- Fire-and-forget: errors are logged but never disrupt the user.
--- This function runs synchronously on the main loop; blocking I/O is acceptable
--- because the file is a few hundred bytes at most.
local function persist_worktree_description(worktree_name, parent_dir, desc)
	local path = parent_dir .. "/worktrees.json"
	local tmp_path = parent_dir .. "/worktrees.json.tmp"

	-- Read existing entries
	local entries = {}
	local ok, err = pcall(function()
		local file = io.open(path, "r")
		if file then
			local content = file:read("*a")
			file:close()
			if content and content ~= "" then
				local decoded = vim.json.decode(content)
				if type(decoded) == "table" then
					entries = decoded
				else
					log.warn("persist_worktree_description: decoded non-table type, resetting")
				end
			end
		end
	end)
	if not ok then
		log.warn("persist_worktree_description: read/decode failed: " .. tostring(err))
		entries = {}
	end

	-- Upsert
	entries[worktree_name] = desc

	-- Prune entries whose directories no longer exist.
	-- This iterates all keys on every write; acceptable because a repo
	-- typically has only 2-5 worktrees.
	for key, _ in pairs(entries) do
		if key ~= worktree_name and vim.fn.isdirectory(parent_dir .. "/" .. key) == 0 then
			entries[key] = nil
		end
	end

	-- Atomic write: tmp file -> rename.
	-- Concurrent instances may race on read-modify-write (last writer wins),
	-- but os.rename is atomic on POSIX so the file is never left corrupt.
	-- Lost entries self-heal on the next prompt from that worktree.
	local write_ok, write_err = pcall(function()
		local file = io.open(tmp_path, "w")
		if not file then
			error("failed to open tmp file for writing")
		end
		file:write(vim.json.encode(entries))
		file:close()
		local rename_ok, rename_err = os.rename(tmp_path, path)
		if not rename_ok then
			error("rename failed: " .. tostring(rename_err))
		end
	end)
	if not write_ok then
		log.warn("persist_worktree_description: write failed: " .. tostring(write_err))
		pcall(os.remove, tmp_path)
	end
end

--- Generate a short pane description from prompt text via LLM and set @desc.
--- Fire-and-forget: errors are logged but never disrupt the user.
local function generate_pane_description(prompt_text, cwd)
	if not prompt_text or prompt_text == "" then
		return
	end
	if vim.fn.executable("opencode") ~= 1 then
		log.debug("generate_pane_description: opencode not found, skipping")
		return
	end
	if not os.getenv("TMUX") then
		log.debug("generate_pane_description: not in tmux, skipping")
		return
	end

	-- Capture the pane ID for this vim instance so we target the correct pane
	-- even when vim loads in a non-focused tab (e.g. via workmux).
	-- $TMUX_PANE is set by tmux when the shell is spawned and is stable
	-- regardless of which pane currently has focus.
	local pane_id = os.getenv("TMUX_PANE")
	if not pane_id then
		log.debug("generate_pane_description: TMUX_PANE not set, skipping")
		return
	end

	-- Derive worktree info for file persistence.
	-- Must be captured synchronously here, not inside the async callback,
	-- because the user's cwd could change before the callback fires.
	local worktree_name = cwd and vim.fn.fnamemodify(cwd, ":t") or nil
	local parent_dir = cwd and vim.fn.fnamemodify(cwd, ":h") or nil
	local parent_name = parent_dir and vim.fn.fnamemodify(parent_dir, ":t") or nil
	local is_main_worktree = (worktree_name == parent_name)

	-- Clear any stale description before the async call
	vim.system({ "tmux", "set", "-pt", pane_id, "@desc" })

	local instructions = "Summarize this task in 3-5 words. "
		.. "Output ONLY the summary, nothing else. "
		.. "No quotes, no punctuation, no explanation."
	local capped_prompt = prompt_text:sub(1, 2000)
	local message = instructions .. " The task: " .. capped_prompt

	vim.system(
		{ "opencode", "run", "--format", "json", "--model", "anthropic/claude-haiku-4-5", message },
		{ timeout = 45000 },
		function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					local stderr_info = ""
					if result.stderr and result.stderr ~= "" then
						stderr_info = " stderr: " .. result.stderr:sub(1, 500)
					end
					log.warn(
						"generate_pane_description: opencode exited with code " .. tostring(result.code) .. stderr_info
					)
					return
				end

				local stdout = result.stdout or ""
				if stdout == "" then
					log.warn("generate_pane_description: empty output")
					return
				end

				-- Parse NDJSON: collect .part.text from all type=="text" objects
				local parts = {}
				for line in stdout:gmatch("[^\n]+") do
					local ok, decoded = pcall(vim.json.decode, line)
					if ok and type(decoded) == "table" and decoded.type == "text" then
						local text = decoded.part and decoded.part.text
						if text then
							table.insert(parts, text)
						end
					end
				end

				local desc = vim.trim(table.concat(parts, " "))
				desc = desc:gsub("[%c]", "")
				desc = desc:sub(1, 50)
				desc = vim.trim(desc)

				if desc == "" then
					log.warn("generate_pane_description: empty after sanitization")
					return
				end

				-- Persist description to worktrees.json (fire-and-forget)
				if worktree_name and parent_dir and not is_main_worktree then
					persist_worktree_description(worktree_name, parent_dir, desc)
				end

				log.info("generate_pane_description: @desc = " .. desc)
				vim.system({ "tmux", "set", "-pt", pane_id, "@desc", desc }, {}, function(tmux_result)
					vim.schedule(function()
						if tmux_result.code ~= 0 then
							log.warn("generate_pane_description: tmux set failed: " .. tostring(tmux_result.code))
						end
					end)
				end)
			end)
		end
	)
end

function M.WorkmuxPrompt()
	-- Find .workmux/PROMPT-*.md in cwd
	local cwd = vim.fn.getcwd()
	local workmux_dir = cwd .. "/.workmux"
	local prompt_files = vim.fn.glob(workmux_dir .. "/PROMPT-*.md", false, true)

	if #prompt_files == 0 then
		return
	end

	-- Use the first prompt file (warn if multiple found)
	local prompt_file = prompt_files[1]
	if #prompt_files > 1 then
		log.warn("Multiple workmux prompts found, using: " .. prompt_file)
	end
	log.info("Found workmux prompt: " .. prompt_file)

	-- Read content before deleting to avoid race with async termopen
	local lines = vim.fn.readfile(prompt_file)
	if #lines == 0 then
		return
	end
	local prompt_text = table.concat(lines, "\n")

	-- Generate a short pane description asynchronously (fire-and-forget)
	generate_pane_description(prompt_text, cwd)

	-- Clean up all prompt files so they aren't re-sent on restart
	for _, f in ipairs(prompt_files) do
		vim.fn.delete(f)
	end

	-- Pass prompt to opencode via --prompt with shellescape for safe shell passing
	-- shellescape wraps in single quotes, which table.concat in claude.lua joins with spaces
	-- Result: opencode /project --prompt 'the prompt text'
	-- Use "current" window type so opencode fills the whole viewport on boot;
	-- a BufEnter autocmd will revert it to a vsplit when a file is opened.
	M.workmux_fullscreen = true
	M.Open("opencode", { "--prompt", vim.fn.shellescape(prompt_text) }, "current")
end

function M.setup(opts)
	opts = opts or {}
	M.auto_build = opts.auto_build ~= false

	-- Log the container name for this instance
	log.info("Neovim instance PID " .. vim.fn.getpid() .. " will use container: " .. M.container_name)

	-- Configure buffer settings
	if opts.buffer_config then
		M.buffer_config = vim.tbl_extend("force", M.buffer_config, opts.buffer_config)
	end
	buffer_config.setup(M.buffer_config)

	-- Configure logging
	if opts.log_level then
		log.set_level(opts.log_level)
	end
	configureClaudeKeymap()

	-- Setup autocmds and user commands
	commands.setup_autocmds(M)
	commands.setup_user_commands(M)
end

return M
