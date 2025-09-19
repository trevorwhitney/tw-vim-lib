local M = {}

local claude = require("tw.claude.claude")
local docker = require("tw.claude.docker")
local Path = require("plenary.path")
local terminal = require("tw.claude.terminal")
local allowed_tools = require("tw.claude.allowed-tools")
local util = require("tw.claude.util")
local log = require("tw.log")
local commands = require("tw.claude.commands")
local buffer_config = require("tw.claude.buffer-config")
local default_args = {}

-- Expose log module globally for claude.lua to use
_G.claude_log = log
-- Separate buffers for docker and local modes
M.docker_buf = nil
M.docker_job_id = nil
M.local_buf = nil
M.local_job_id = nil
M.active_mode = "docker" -- Track which mode is currently visible: "docker", "local", or "none"

-- Legacy claude_buf/job_id will point to the active buffer
M.claude_buf = nil
M.claude_job_id = nil

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
M.auto_prompt = true -- Send prompt automatically on startup
M.auto_prompt_file = "coding.md" -- Default prompt file to send

-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount at /context/*

-- Buffer configuration
M.buffer_config = {
	scrollback = 5000,
	follow_output = true,
	prevent_resize_scroll = true,
}

-- Find the plugin installation path
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/init%.lua$")
	return plugin_root
end

local function OnExit(mode)
	return function(job_id, exit_code, event_type)
		vim.schedule(function()
			local buf = mode == "docker" and M.docker_buf or M.local_buf
			if buf and vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_set_option(buf, "modifiable", true)
				local message
				if exit_code == 0 then
					message = "Claude process completed successfully."
				else
					message = "Claude process exited with code: " .. exit_code
				end
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", message })
				vim.api.nvim_buf_set_option(buf, "modifiable", false)
			end
			-- Clear buffer and job state when process exits
			if mode == "docker" then
				M.docker_buf = nil
				M.docker_job_id = nil
			else
				M.local_buf = nil
				M.local_job_id = nil
			end
			-- Update legacy pointers if this was the active buffer
			if M.claude_buf == buf then
				M.claude_buf = nil
				M.claude_job_id = nil
				M.active_mode = "none"
			end
		end)
	end
end

local function start_new_claude_job(args, window_type, mode)
	mode = mode or "docker"
	log.info("Attempting to start new Claude job in " .. mode .. " mode")
	-- Launch Claude
	local command
	local buf, job_id

	if mode == "docker" then
		log.debug("Docker mode enabled, checking container status")
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
		command = docker.attach_to_container(M.container_name, cmd_args)
		log.debug("Using attach command: " .. command)
	else
		log.debug("Local mode enabled")
		-- For local mode, include allowedTools
		local final_args = vim.tbl_extend("force", {}, default_args)
		table.insert(final_args, '--allowedTools="' .. table.concat(allowed_tools, ",") .. '"')
		if args and #args > 0 then
			vim.list_extend(final_args, args)
		end
		command = claude.command(final_args)
		log.debug("Using native command: " .. command)
	end

	log.info("Starting Claude with command: " .. command)

	-- Hide the other mode's buffer if it's visible before opening new window
	local other_buf = mode == "docker" and M.local_buf or M.docker_buf
	if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
		local windows = vim.api.nvim_list_wins()
		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == other_buf then
				vim.api.nvim_win_close(win, false)
				break
			end
		end
	end

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
	if mode == "docker" then
		M.docker_buf = buf
		M.docker_job_id = job_id
	else
		M.local_buf = buf
		M.local_job_id = job_id
	end

	-- Update active mode and legacy pointers
	M.active_mode = mode
	M.claude_buf = buf
	M.claude_job_id = job_id

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
	local job_id = M.claude_job_id
	if not job_id then
		-- Try to get from active mode
		if M.active_mode == "docker" then
			job_id = M.docker_job_id
		elseif M.active_mode == "local" then
			job_id = M.local_job_id
		end
	end
	if job_id then
		vim.fn.chansend(job_id, text)
	else
		log.warn("No active Claude job to send to")
	end
end

local function confirmOpenAndDo(callback, args, window_type)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Determine which buffer to use (default to docker if none active)
	local active_buf = M.claude_buf
	if not active_buf or not vim.api.nvim_buf_is_valid(active_buf) then
		-- No active buffer, default to docker mode
		M.Open("docker", args, window_type)

		-- Wait a bit for the Claude chat to initialize
		vim.defer_fn(function()
			if callback then
				callback()
			end
			-- Focus Claude buffer and enter insert mode
			if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
				local windows = vim.api.nvim_list_wins()
				for _, win in ipairs(windows) do
					if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
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
	mode = mode or "docker" -- Default to docker mode
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Get the appropriate buffer and job for the mode
	local buf, job_id
	if mode == "docker" then
		buf = M.docker_buf
		job_id = M.docker_job_id
	else
		buf = M.local_buf
		job_id = M.local_job_id
	end

	-- Check if buffer exists, is valid, AND the job is still running
	local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

	if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
		-- First, hide the other mode's buffer if it's visible
		local other_buf = mode == "docker" and M.local_buf or M.docker_buf
		if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
			local windows = vim.api.nvim_list_wins()
			for _, win in ipairs(windows) do
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == other_buf then
					vim.api.nvim_win_close(win, false)
					break
				end
			end
		end
		terminal.open_buffer_in_new_window(window_type, buf)
		-- Update active mode and legacy pointers
		M.active_mode = mode
		M.claude_buf = buf
		M.claude_job_id = job_id
	else
		-- Clean up dead buffer if needed
		if buf and not job_is_running then
			local cleaned_buf, cleaned_job = terminal.close_terminal_buffer(buf, job_id)
			if mode == "docker" then
				M.docker_buf = cleaned_buf
				M.docker_job_id = cleaned_job
			else
				M.local_buf = cleaned_buf
				M.local_job_id = cleaned_job
			end
		end
		start_new_claude_job(args, window_type, mode)
	end
end

function M.Toggle(mode, args, window_type)
	mode = mode or "docker" -- Default to docker if not specified
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Get the appropriate buffer and job based on mode
	local buf, job_id
	if mode == "docker" then
		buf = M.docker_buf
		job_id = M.docker_job_id
	else
		buf = M.local_buf
		job_id = M.local_job_id
	end

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
				if M.claude_buf == buf then
					M.active_mode = "none"
					M.claude_buf = nil
					M.claude_job_id = nil
				end
				break
			end
		end

		-- If buffer exists but is not visible, show it in window_type
		if not is_visible then
			-- First, hide the other mode's buffer if it's visible
			local other_buf = mode == "docker" and M.local_buf or M.docker_buf
			if other_buf and vim.api.nvim_buf_is_valid(other_buf) then
				local windows = vim.api.nvim_list_wins()
				for _, win in ipairs(windows) do
					if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == other_buf then
						vim.api.nvim_win_close(win, false)
						break
					end
				end
			end
			terminal.open_buffer_in_new_window(window_type, buf)
			-- Update active mode and legacy pointers
			M.active_mode = mode
			M.claude_buf = buf
			M.claude_job_id = job_id
		end
	else
		-- Buffer doesn't exist or job is dead, clean up and create new
		if buf and not job_is_running then
			local cleaned_buf, cleaned_job = terminal.close_terminal_buffer(buf, job_id)
			M.docker_buf = cleaned_buf
			M.docker_job_id = cleaned_job
		end
		M.Open(mode, args, window_type)
	end
end

-- Helper function to hide all Claude buffers
function M.hide_all_claude_buffers()
	local windows = vim.api.nvim_list_wins()
	for _, win in ipairs(windows) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if buf == M.docker_buf or buf == M.local_buf then
				vim.api.nvim_win_close(win, false)
			end
		end
	end
end

local function submit()
	vim.defer_fn(function()
		local job_id = M.claude_job_id
		if not job_id then
			-- Try to get from active mode
			if M.active_mode == "docker" then
				job_id = M.docker_job_id
			elseif M.active_mode == "local" then
				job_id = M.local_job_id
			end
		end
		if job_id then
			vim.fn.chansend(job_id, "\r")
		else
			log.warn("No active Claude job to submit to")
		end
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
		"the code snippet from @" .. rel_path .. "\n",
		"```\n",
	})
	send(args)
	send({
		"\n```\n",
	})
end

function M.SendSelection()
	-- Get the current selection while in visual mode
	vim.cmd('normal! "sy')

	-- Get the content of the register
	local selection = vim.fn.getreg("s")

	-- Get the current file path
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())

	-- Exit visual mode before opening Claude
	vim.cmd("normal! \027") -- \027 is escape key

	confirmOpenAndDo(function()
		-- Send the prompt
		sendCodeSnippet(selection, rel_path)
		-- Don't return to visual mode since we're now in Claude buffer
	end)
end

function M.SendSymbol()
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())
	local word = vim.fn.expand("<cword>")
	confirmOpenAndDo(function()
		M.SendText({
			word,
			"in @" .. rel_path .. " ",
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
		{ "<leader>c", group = "Claude Code", nowait = true, remap = false },
		{
			mode = { "n", "v" },
			{
				"<leader>cd",
				function()
					require("tw.claude").Toggle("docker")
				end,
				desc = "Toggle Claude Docker",
			},
			{
				"<leader>cl",
				function()
					require("tw.claude").Toggle("local")
				end,
				desc = "Toggle Claude Local",
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
					require("tw.claude").SendSymbol()
				end,
				desc = "Send Current Word to Claude",
				nowait = false,
				remap = false,
			},
			{
				"<leader>cf",
				function()
					require("tw.claude").SendFile()
				end,
				desc = "Send File to Claude",
				nowait = false,
				remap = false,
			},
			{
				"<leader>ct",
				function()
					require("tw.claude").SendPrompt("tdd-plan.md", true)
				end,
				desc = "Send TDD Plan to Claude",
				nowait = false,
				remap = false,
			},
			{
				"<leader>cm",
				function()
					require("tw.claude").SendPrompt("commit-staged.md", true)
				end,
				desc = "Commit Staged with Claude",
				nowait = false,
				remap = false,
			},
			{
				"<leader>ci",
				function()
					require("tw.claude").SendPrompt("implement.md", true)
				end,
				desc = "Implement the failing test with Claude",
				nowait = false,
				remap = false,
			},
			{
				"<leader>cb",
				function()
					require("tw.claude").SendOpenBuffers()
				end,
				desc = "Send TDD Plan to Claude",
				nowait = false,
				remap = false,
			},
		},
		{
			mode = { "v" },
			{
				"<leader>c*",
				function()
					require("tw.claude").SendSelection()
				end,
				desc = "Send Selection to Claude",
				nowait = false,
				remap = false,
			},
		},
	}

	local wk = require("which-key")
	wk.add(keymap)
end

function M.cleanup()
	-- Clean up docker job and buffer config
	if M.docker_job_id and vim.fn.jobwait({ M.docker_job_id }, 0)[1] == -1 then
		vim.fn.jobstop(M.docker_job_id)
		M.docker_job_id = nil
	end
	if M.docker_buf then
		buffer_config.cleanup(M.docker_buf)
	end
	-- Clean up local job and buffer config
	if M.local_job_id and vim.fn.jobwait({ M.local_job_id }, 0)[1] == -1 then
		vim.fn.jobstop(M.local_job_id)
		M.local_job_id = nil
	end
	if M.local_buf then
		buffer_config.cleanup(M.local_buf)
	end
	-- Clean up legacy pointers
	M.claude_job_id = nil
	M.claude_buf = nil

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
