local M = {}

local claude = require("tw.claude.claude")
local docker = require("tw.claude.docker")
local Path = require("plenary.path")
local terminal = require("tw.claude.terminal")
local allowed_tools = require("tw.claude.allowed-tools")
local util = require("tw.claude.util")
local log = require("tw.log")
local commands = require("tw.claude.commands")
local default_args = {}

-- Expose log module globally for claude.lua to use
_G.claude_log = log
M.claude_buf = nil
M.claude_job_id = nil
M.saved_updatetime = nil
M.shell_buf = nil
M.shell_job_id = nil
M.logs_buf = nil
M.logs_job_id = nil

-- Docker mode configuration
M.docker_mode = true -- DEFAULT TO DOCKER MODE
M.auto_build = true -- Auto-build image if missing
M.container_started = false -- Track if we started the container
M.container_name = string.format("claude-code-nvim-%d-%d", vim.fn.getpid(), os.time()) -- More unique container name
-- Auto-prompt configuration
M.auto_prompt = true -- Send prompt automatically on startup
M.auto_prompt_file = "coding.md" -- Default prompt file to send

-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount at /context/*

-- Find the plugin installation path
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/init%.lua$")
	return plugin_root
end

local function OnExit(job_id, exit_code, event_type)
	vim.schedule(function()
		if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) then
			vim.api.nvim_buf_set_option(M.claude_buf, "modifiable", true)
			local message
			if exit_code == 0 then
				message = "Claude process completed successfully."
			else
				message = "Claude process exited with code: " .. exit_code
			end
			vim.api.nvim_buf_set_lines(M.claude_buf, -1, -1, false, { "", message })
			vim.api.nvim_buf_set_option(M.claude_buf, "modifiable", false)
		end
		-- Clear buffer and job state when process exits
		M.claude_buf = nil
		M.claude_job_id = nil
	end)
end

local function start_new_claude_job(args, window_type)
	log.info("Attempting to start new Claude job")
	-- Launch Claude
	local command
	if M.docker_mode then
		log.debug("Docker mode enabled, checking container status")
		-- Check if container is running, if not try to start it
		local is_running, container_id, status = docker.is_container_running(M.container_name)
		log.debug("Container running check result: " .. tostring(is_running))
		log.debug("Container ID: " .. (container_id or "none"))
		log.debug("Container status: " .. (status or "unknown"))
		log.debug("Container started flag: " .. tostring(M.container_started))

		if not is_running then
			if M.container_started then
				-- Container was started but isn't running - try to restart it
				log.warn("Container was started but is not running, attempting restart", true)
				docker.ensure_container_stopped(M.container_name)
				local success, result = docker.start_persistent_container(M.container_name)
				if not success then
					log.error("Failed to restart container: " .. (result or "Unknown error"), true)
					M.docker_mode = false
					M.container_started = false
				end
			else
				log.error("Container not running and not started by this session", true)
				return
			end
		end

		local cmd_args = ""
		if args and #args > 0 then
			cmd_args = table.concat(args, " ")
		end
		command = docker.attach_to_container(M.container_name, cmd_args)
		log.debug("Using attach command: " .. command)
	else
		log.debug("Native mode enabled")
		-- For non-docker mode, include allowedTools
		local final_args = vim.tbl_extend("force", {}, default_args)
		table.insert(final_args, '--allowedTools="' .. table.concat(allowed_tools, ",") .. '"')
		if args and #args > 0 then
			vim.list_extend(final_args, args)
		end
		command = claude.command(final_args)
		log.debug("Using native command: " .. command)
	end
	log.info("Starting Claude with command: " .. command)
	terminal.open_window(window_type)
	M.claude_buf = vim.api.nvim_get_current_buf()
	M.claude_job_id = vim.fn.termopen(command, {
		on_exit = OnExit,
		-- TODO: make this configurable
		env = {
			BUILD_IN_CONTAINER = "false",
		},
	})
	vim.bo[M.claude_buf].bufhidden = "hide"
	vim.bo[M.claude_buf].filetype = "ClaudeConsole"

	-- Auto-send prompt if enabled (works for both Docker and native modes)
	if M.auto_prompt and M.auto_prompt_file then
		vim.defer_fn(function()
			log.debug("Sending auto-prompt: " .. M.auto_prompt_file)
			M.SendPrompt(M.auto_prompt_file, true)
			vim.cmd("startinsert")
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
	vim.fn.chansend(M.claude_job_id, text)
end

local function confirmOpenAndDo(callback, args, window_type)
	args = args or default_args
	window_type = window_type or "vsplit"
	if not M.claude_buf or not vim.api.nvim_buf_is_valid(M.claude_buf) then
		-- Buffer doesn't exist, open it
		M.Open(args, window_type)

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
		end, 1500)
	else
		-- Buffer exists, make sure it's visible
		local windows = vim.api.nvim_list_wins()
		local is_visible = false
		local claude_win = nil

		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
				-- Buffer is visible
				is_visible = true
				claude_win = win
				break
			end
		end

		-- If buffer exists but is not visible, show it in window_type
		if not is_visible then
			terminal.open_buffer_in_new_window(window_type, M.claude_buf)
			-- Find the new window
			windows = vim.api.nvim_list_wins()
			for _, win in ipairs(windows) do
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
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

function M.Open(args, window_type)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Check if buffer exists, is valid, AND the job is still running
	local job_is_running = M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1

	if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) and job_is_running then
		terminal.open_buffer_in_new_window(window_type, M.claude_buf)
	else
		-- Clean up dead buffer if needed
		if M.claude_buf and not job_is_running then
			local buf, job = terminal.close_terminal_buffer(M.claude_buf, M.claude_job_id)
			M.claude_buf = buf
			M.claude_job_id = job
		end
		start_new_claude_job(args, window_type)
	end
end

function M.Toggle(args, window_type)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Check if buffer exists, is valid, AND the job is still running
	local job_is_running = M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1

	if M.claude_buf and vim.api.nvim_buf_is_valid(M.claude_buf) and job_is_running then
		-- Buffer exists and job is running - toggle visibility
		local windows = vim.api.nvim_list_wins()
		local is_visible = false

		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.claude_buf then
				-- Buffer is visible, hide it by closing the window
				vim.api.nvim_win_close(win, false)
				is_visible = true
				break
			end
		end

		-- If buffer exists but is not visible, show it in window_type
		if not is_visible then
			terminal.open_buffer_in_new_window(window_type, M.claude_buf)
		end
	else
		-- Buffer doesn't exist or job is dead, clean up and create new
		if M.claude_buf and not job_is_running then
			local buf, job = terminal.close_terminal_buffer(M.claude_buf, M.claude_job_id)
			M.claude_buf = buf
			M.claude_job_id = job
		end
		M.Open(args, window_type)
	end
end

local function submit()
	vim.defer_fn(function()
		vim.fn.chansend(M.claude_job_id, "\r")
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
		"take a look at the following code snippet from @" .. rel_path .. "\n",
		"```\n",
	})
	send(args)
	send({
		"```\n",
	})
end

function M.SendSelection()
	-- Get the current selection
	vim.cmd('normal! "sy')

	-- Get the content of the register x
	local selection = vim.fn.getreg("s")

	-- Get the current file path
	local filename = vim.fn.expand("%")
	local rel_path = Path:new(filename):make_relative(util.get_git_root())
	confirmOpenAndDo(function()
		-- Send the prompt
		sendCodeSnippet(selection, rel_path)

		-- Return to visual mode
		vim.cmd("normal! gv")
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
				"<leader>cl",
				function()
					require("tw.claude").Toggle()
				end,
				desc = "Toggle Claude",
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
	if M.claude_job_id and vim.fn.jobwait({ M.claude_job_id }, 0)[1] == -1 then
		vim.fn.jobstop(M.claude_job_id)
		M.claude_job_id = nil
	end
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

function M.setup(opts)
	opts = opts or {}
	M.docker_mode = opts.docker_mode ~= false -- Docker mode unless explicitly disabled
	M.auto_build = opts.auto_build ~= false

	-- Log the container name for this instance
	if M.docker_mode then
		log.info("Neovim instance PID " .. vim.fn.getpid() .. " will use container: " .. M.container_name)
	end

	-- Configure auto-prompt
	if opts.auto_prompt ~= nil then
		M.auto_prompt = opts.auto_prompt
	end
	if opts.auto_prompt_file then
		M.auto_prompt_file = opts.auto_prompt_file
	end

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
