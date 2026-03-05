local M = {}

local claude = require("tw.agent.claude")
local docker = require("tw.agent.docker")
local Path = require("plenary.path")
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
M.active_mode = "claude" -- Track which mode is currently visible: "claude", "claude-docker", "codex", "codex-docker", "opencode", "opencode-docker", or "none"

-- Active buffer/job_id points to the currently visible buffer
M.active_buf = nil
M.active_job_id = nil

M.saved_updatetime = nil
M.shell_buf = nil
M.shell_job_id = nil
M.logs_buf = nil
M.logs_job_id = nil

-- Container configuration
M.auto_build = true -- Auto-build image if missing
M.container_started = false -- Track if we started the container
M.container_name = string.format("claude-code-nvim-%d-%d", vim.fn.getpid(), os.time()) -- More unique container name
-- Auto-prompt configuration
M.auto_prompt = false -- Send prompt automatically on startup
M.auto_prompt_file = "coding.md" -- Default prompt file to send

-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount at /context/*

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
				-- In docker mode, ensure git root is in context_directories and use the mounted container path
				if not M.context_directories[git_root] then
					M.context_directories[git_root] = true
					log.info("Auto-added git root to context directories: " .. git_root)
				end

				local dir_name = vim.fn.fnamemodify(git_root, ":t")
				-- Check if there's a duplicate to determine the mount name
				local has_duplicate = false
				for other_path, _ in pairs(M.context_directories) do
					if other_path ~= git_root and vim.fn.fnamemodify(other_path, ":t") == dir_name then
						has_duplicate = true
						break
					end
				end
				local mount_name = dir_name
				if has_duplicate then
					local hash = vim.fn.sha256(git_root)
					mount_name = dir_name .. "_" .. string.sub(hash, 1, 8)
				end
				project_path = "/context/" .. mount_name
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
				docker.start_container_async(
					M.container_name,
					M.auto_build,
					M.context_directories,
					function(success, status)
						if success then
							M.container_started = true
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
		-- Use the command name from the parsed mode
		command = docker.attach_to_container(M.container_name, cmd_args, command_name)
		log.debug("Using docker attach command: " .. command)
	else
		log.debug("Local mode enabled for " .. command_name)
		-- For local mode, skip permissions for all agents
		local final_args = vim.tbl_extend("force", {}, default_args)
		if command_name ~= "opencode" then
			table.insert(final_args, "--dangerously-skip-permissions")
			log.debug("Added --dangerously-skip-permissions for " .. command_name)
		end
		if args and #args > 0 then
			log.debug("Extending final_args with " .. #args .. " args")
			vim.list_extend(final_args, args)
		end
		log.debug("Final args before command: " .. vim.inspect(final_args))
		command = claude.command(final_args, command_name)
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

	-- Auto-send prompt if enabled (works for both Docker and local modes)
	if M.auto_prompt and M.auto_prompt_file then
		vim.defer_fn(function()
			log.debug("Sending auto-prompt: " .. M.auto_prompt_file)
			M.SendPrompt(M.auto_prompt_file, true)
			vim.defer_fn(function()
				vim.cmd("startinsert")
			end, 500)
		end, 1750)
	else
		vim.defer_fn(function()
			vim.cmd("startinsert")
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
		-- No active buffer, default to claude local mode
		M.Open("claude", args, window_type)

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
	vim.cmd('normal! "sy')

	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")

	-- Get the current file path
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())

	-- Exit visual mode before opening Claude
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
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())
	local word = vim.fn.expand("<cword>")
	local line_num = vim.fn.line(".")
	confirmOpenAndDo(function()
		M.SendText({
			word .. " @" .. rel_path .. ":" .. line_num .. " ",
		})
	end)
end

function M.SendFile()
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())
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
				"<leader>ct",
				function()
					require("tw.agent").SendPrompt("tdd-plan.md", true)
				end,
				desc = "Send TDD Plan to AI Agent",
				nowait = false,
				remap = false,
			},
			{
				"<leader>cm",
				function()
					require("tw.agent").SendPrompt("commit-staged.md", true)
				end,
				desc = "Commit Staged with AI Agent",
				nowait = false,
				remap = false,
			},
			{
				"<leader>ci",
				function()
					require("tw.agent").SendPrompt("implement.md", true)
				end,
				desc = "Implement the failing test with AI Agent",
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

function M.setup(opts)
	opts = opts or {}
	M.auto_build = opts.auto_build ~= false

	-- Log the container name for this instance
	log.info("Neovim instance PID " .. vim.fn.getpid() .. " will use container: " .. M.container_name)

	-- Configure auto-prompt
	if opts.auto_prompt ~= nil then
		M.auto_prompt = opts.auto_prompt
	end
	if opts.auto_prompt_file then
		M.auto_prompt_file = opts.auto_prompt_file
	end

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
