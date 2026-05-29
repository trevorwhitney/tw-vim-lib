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
-- Single source of truth for the default agent.
-- Change this value to switch every default (Open, Toggle, WorkmuxPrompt, etc.).
M.default_mode = "pi"
M.active_mode = "none" -- currently visible mode, or "none" when no agent is shown
M.active_index = 0     -- idx of the visible/last-shown instance

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
M.agent_fullscreen = false

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

-- =====================================================================
-- Multi-instance data model
-- =====================================================================
M.instances = {
  pi                  = {},
  opencode            = {},
  claude              = {},
  codex               = {},
  ["pi-docker"]       = {},
  ["opencode-docker"] = {},
  ["claude-docker"]   = {},
  ["codex-docker"]    = {},
}

local function get_instance(mode, idx)
  idx = idx or 0
  M.instances[mode] = M.instances[mode] or {}
  return M.instances[mode][idx]
end

local function set_instance(mode, idx, buf, job_id)
  idx = idx or 0
  M.instances[mode] = M.instances[mode] or {}
  M.instances[mode][idx] = { buf = buf, job_id = job_id }
end

local function clear_instance(mode, idx)
  idx = idx or 0
  if M.instances[mode] then
    M.instances[mode][idx] = nil
  end
end

local function iter_all_instances()
  local modes = vim.tbl_keys(M.instances)
  table.sort(modes)
  local mi, idx_keys, ii = 1, nil, 0
  return function()
    while mi <= #modes do
      local mode = modes[mi]
      if not idx_keys then
        idx_keys = vim.tbl_keys(M.instances[mode] or {})
        table.sort(idx_keys)
        ii = 0
      end
      ii = ii + 1
      if ii <= #idx_keys then
        local idx = idx_keys[ii]
        local inst = M.instances[mode][idx]
        if inst then return mode, idx, inst.buf, inst.job_id end
      else
        mi, idx_keys = mi + 1, nil
      end
    end
    return nil
  end
end

-- Stable internal API for the plenary spec suite. Not for external use.
M._get_instance       = get_instance
M._set_instance       = set_instance
M._clear_instance     = clear_instance
M._iter_all_instances = iter_all_instances

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

local function OnExit(mode, idx)
  return function(exited_job_id, _, _)
    -- Stale-callback guard: if a newer instance has taken this slot
    -- (e.g. after restart_local_agent), don't clear it. We're seeing
    -- the *prior* job's OnExit callback fire after we've already
    -- spawned and stored a fresh instance at (mode, idx).
    local inst = get_instance(mode, idx)
    if not inst or inst.job_id ~= exited_job_id then
      return
    end
    clear_instance(mode, idx)
    if M.active_mode == mode and M.active_index == idx then
      M.active_mode   = "none"
      M.active_index  = 0
      M.active_buf    = nil
      M.active_job_id = nil
    end
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

local function close_other_agent_buffers(target_mode, target_idx)
  target_idx = target_idx or 0
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) then
      local win_buf = vim.api.nvim_win_get_buf(win)
      for mode, idx, buf, _ in iter_all_instances() do
        if win_buf == buf and not (mode == target_mode and idx == target_idx) then
          vim.api.nvim_win_close(win, false)
          break
        end
      end
    end
  end
end

local function start_new_agent_job(args, window_type, mode, idx)
	mode = mode or M.default_mode
	idx = idx or 0
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
	close_other_agent_buffers(mode, idx)

	terminal.open_window(window_type)
	buf = vim.api.nvim_get_current_buf()
	job_id = vim.fn.termopen(command, {
		on_exit = OnExit(mode, idx),
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

	-- Store via the multi-instance helper
	set_instance(mode, idx, buf, job_id)
	-- Set the agent:// buffer name for identification (must happen BEFORE
	-- any consumer reads the name)
	pcall(vim.api.nvim_buf_set_name, buf, string.format("agent://%s#%d", mode, idx))

	-- Update active state
	M.active_mode   = mode
	M.active_index  = idx
	M.active_buf    = buf
	M.active_job_id = job_id

	vim.defer_fn(function()
		vim.cmd("startinsert")
	end, 500)
end

local function send(job_id, args)
	if not job_id then
		log.warn("No job to send to")
		return
	end
	local text = ""
	if type(args) == "string" then
		text = args
	elseif type(args) == "table" and args and #args > 0 then
		text = table.concat(args, " ")
	end
	vim.fn.chansend(job_id, text)
end

-- Resolve the (mode, idx) target for a send command based on a count value.
-- count == 0: use active instance, or spawn default_mode#0 if no active
-- count > 0:  use (active_mode || default_mode, count), spawn-and-show if missing
-- count > 9:  notify and return nil
local function resolve_send_target(count)
	if count > 9 then
		vim.notify(
			string.format("Agent instance index must be 0-9 (got %d)", count),
			vim.log.levels.WARN
		)
		return nil
	end

	if count == 0 then
		if M.active_mode ~= "none" then
			return M.active_mode, M.active_index
		end
		M.Open(M.default_mode, nil, "vsplit", 0)
		return M.default_mode, 0
	end

	-- count > 0: explicit ternary — literal "none" is truthy in Lua, so plain
	-- `M.active_mode or M.default_mode` would not fall through.
	local mode = (M.active_mode ~= "none") and M.active_mode or M.default_mode
	local inst = get_instance(mode, count)
	local alive = inst and inst.job_id and vim.fn.jobwait({ inst.job_id }, 0)[1] == -1
	if not alive then
		M.Open(mode, nil, "vsplit", count)
	end
	return mode, count
end

M._resolve_send_target = resolve_send_target

local function confirmOpenAndDo(callback, args, window_type, target_mode, target_idx)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Explicit target path: route to a specific (mode, idx) instance.
	if target_mode then
		local inst = get_instance(target_mode, target_idx)
		local alive = inst
			and inst.buf and vim.api.nvim_buf_is_valid(inst.buf)
			and inst.job_id and vim.fn.jobwait({ inst.job_id }, 0)[1] == -1
		if not alive then
			M.Open(target_mode, args, window_type, target_idx)
			vim.defer_fn(function()
				if callback then callback() end
			end, 2500)
			return
		end
		-- Ensure the target buf is visible
		local visible = false
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == inst.buf then
				visible = true
				break
			end
		end
		if not visible then
			close_other_agent_buffers(target_mode, target_idx)
			terminal.open_buffer_in_new_window(window_type, inst.buf)
		end
		M.active_mode, M.active_index  = target_mode, target_idx
		M.active_buf,  M.active_job_id = inst.buf, inst.job_id
		if callback then callback() end
		return
	end

	-- Legacy fallback: no explicit target, fall back to active state.
	local active_buf = M.active_buf
	if not active_buf or not vim.api.nvim_buf_is_valid(active_buf) then
		-- No active buffer, use active_mode (or fall back to claude)
		-- Active mode may be "none" at startup (or after all agents closed).
		-- Resolve to default_mode in that case so we don't try to open mode="none".
		local fallback_mode = (M.active_mode ~= "none") and M.active_mode or M.default_mode
		local fallback_idx  = (M.active_mode ~= "none") and M.active_index or 0
		M.Open(fallback_mode, args, window_type, fallback_idx)

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

function M.Open(mode, args, window_type, idx)
  mode        = mode or M.default_mode
  args        = args or default_args
  window_type = window_type or "vsplit"
  idx         = idx or 0

  local inst = get_instance(mode, idx)
  local buf, job_id
  if inst then buf, job_id = inst.buf, inst.job_id end

  local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

  if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
    close_other_agent_buffers(mode, idx)
    terminal.open_buffer_in_new_window(window_type, buf)
    M.active_mode   = mode
    M.active_index  = idx
    M.active_buf    = buf
    M.active_job_id = job_id
  else
    if buf and not job_is_running then
      terminal.close_terminal_buffer(buf, job_id)
      clear_instance(mode, idx)
    end
    start_new_agent_job(args, window_type, mode, idx)
  end
end

-- Restart the active local (sandboxed) agent with updated context_directories.
-- Used by add-context/remove-context. Returns true if restarted, false if no
-- local agent was running. Args are not preserved on restart — git root is
-- re-derived in start_new_agent_job().
function M.restart_local_agent()
  local local_modes = { claude = true, codex = true, opencode = true, pi = true }
  local target_mode, target_idx

  -- (a) Prefer the active instance if it's local and alive
  if local_modes[M.active_mode] then
    local inst = get_instance(M.active_mode, M.active_index)
    if inst and inst.job_id and vim.fn.jobwait({ inst.job_id }, 0)[1] == -1 then
      target_mode, target_idx = M.active_mode, M.active_index
    end
  end

  -- (b) Otherwise, deterministic first-live scan via iter_all_instances
  -- (sorted by mode name then idx ascending)
  if not target_mode then
    for m, i, _, j in iter_all_instances() do
      if local_modes[m] and j and vim.fn.jobwait({ j }, 0)[1] == -1 then
        target_mode, target_idx = m, i
        break
      end
    end
  end

  if not target_mode then return false end

  local inst = get_instance(target_mode, target_idx)
  if inst and inst.buf then
    terminal.close_terminal_buffer(inst.buf, inst.job_id)
  end
  clear_instance(target_mode, target_idx)
  if M.active_mode == target_mode and M.active_index == target_idx then
    M.active_mode   = "none"
    M.active_index  = 0
    M.active_buf    = nil
    M.active_job_id = nil
  end
  M.Open(target_mode, nil, "vsplit", target_idx)
  return true
end

function M.Toggle(mode, args, window_type, idx)
  mode        = mode or M.default_mode
  args        = args or default_args
  window_type = window_type or "vsplit"
  idx         = idx or 0

  local inst = get_instance(mode, idx)
  local buf, job_id
  if inst then buf, job_id = inst.buf, inst.job_id end

  local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

  if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
    local visible_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        visible_win = win
        break
      end
    end

    if visible_win then
      vim.api.nvim_win_close(visible_win, false)
      if M.active_mode == mode and M.active_index == idx then
        M.active_mode   = "none"
        M.active_index  = 0
        M.active_buf    = nil
        M.active_job_id = nil
      end
    else
      close_other_agent_buffers(mode, idx)
      terminal.open_buffer_in_new_window(window_type, buf)
      M.active_mode   = mode
      M.active_index  = idx
      M.active_buf    = buf
      M.active_job_id = job_id
    end
  else
    if buf and not job_is_running then
      terminal.close_terminal_buffer(buf, job_id)
      clear_instance(mode, idx)
    end
    M.Open(mode, args, window_type, idx)
  end
end

-- Helper function to hide all agent buffers
function M.hide_all_agent_buffers()
	for _, _, buf, _ in iter_all_instances() do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			close_buffer_windows(buf)
		end
	end
	M.active_mode = "none"
	M.active_index = 0
	M.active_buf = nil
	M.active_job_id = nil
end

-- Backwards compatibility alias
M.hide_all_claude_buffers = M.hide_all_agent_buffers

local function submit(job_id)
	vim.defer_fn(function()
		if job_id then
			vim.fn.chansend(job_id, "\r")
		else
			log.warn("No job to submit to")
		end
	end, 500)
end

-- Internal dispatcher: resolves target via resolve_send_target, ensures the
-- target instance is alive and visible, then runs the named send function's
-- logic with an explicit job_id (no reliance on M.active_job_id).
--
-- Exposed as M._send_with_count so tests and keymap wrappers can call it
-- with an explicit count (vim.v.count is read-only and can't be set from
-- Lua, so tests pass count directly).
function M._send_with_count(fn_name, count, ...)
	local extra = { ... }
	local mode, idx = resolve_send_target(count)
	if not mode then return end

	confirmOpenAndDo(function()
		local inst = get_instance(mode, idx)
		if not inst or not inst.job_id then
			log.warn(string.format("Send target %s#%d has no job_id", mode, idx))
			return
		end
		local job_id = inst.job_id

		if fn_name == "SendCommand" then
			local args = extra[1]
			local submit_after = extra[2] or false
			vim.fn.chansend(job_id, "!")
			vim.defer_fn(function()
				send(job_id, args)
				if submit_after then submit(job_id) end
			end, 500)

		elseif fn_name == "SendText" then
			local args = extra[1]
			local submit_after = extra[2] or false
			send(job_id, args)
			if submit_after then submit(job_id) end

		elseif fn_name == "SendSelection" then
			-- precomputed reference text passed in via extra[1]
			send(job_id, extra[1])

		elseif fn_name == "SendSymbol" then
			send(job_id, extra[1])  -- precomputed reference

		elseif fn_name == "SendFile" then
			send(job_id, extra[1])  -- precomputed reference

		elseif fn_name == "SendOpenBuffers" then
			-- Three-line context message; submit after
			send(job_id, extra[1])
			submit(job_id)
		else
			log.warn("Unknown send function: " .. tostring(fn_name))
		end
	end, nil, "vsplit", mode, idx)
end

function M.SendCommand(args, submit_after)
	M._send_with_count("SendCommand", vim.v.count, args, submit_after or false)
end

function M.SendText(args, submit_after)
	M._send_with_count("SendText", vim.v.count, args, submit_after or false)
end

function M.VimTestStrategy(cmd)
	M.SendCommand({ cmd })
end

function M.SendSelection()
	local Path = require("plenary.path")
	local filename, repo_root = util.resolve_file_path()
	if not filename then
		vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
		return
	end
	local git_root = repo_root or util.get_git_root()
	local rel_path = Path:new(filename):make_relative(git_root)

	vim.cmd('normal! "sy')
	local start_line = vim.fn.line("'<")
	local end_line   = vim.fn.line("'>")
	vim.cmd("normal! \027")

	local reference
	if start_line == end_line then
		reference = "@" .. rel_path .. ":" .. start_line .. " "
	else
		reference = "@" .. rel_path .. ":" .. start_line .. "-" .. end_line .. " "
	end

	M._send_with_count("SendSelection", vim.v.count, reference)
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
	local word     = vim.fn.expand("<cword>")
	local line_num = vim.fn.line(".")
	local reference = word .. " @" .. rel_path .. ":" .. line_num .. " "

	M._send_with_count("SendSymbol", vim.v.count, reference)
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
	local reference = "@" .. rel_path .. " "

	M._send_with_count("SendFile", vim.v.count, reference)
end

function M.SendOpenBuffers()
	local files = util.get_buffer_files()

	if #files == 0 then
		vim.notify("No file buffers found to pass to Claude", vim.log.levels.WARN)
		return
	end

	local message = table.concat({
		"For context, please load the following files:\n",
		table.concat(files, " ") .. "\n",
		"Load the files then wait for my instructions.",
	})

	M._send_with_count("SendOpenBuffers", vim.v.count, message)
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
			{
				"<leader>cp",
				function()
					require("tw.agent").Toggle("pi")
				end,
				desc = "Toggle Pi Local",
			},
			{
				"<leader>cP",
				function()
					require("tw.agent").Toggle("pi-docker")
				end,
				desc = "Toggle Pi Docker",
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
	for _, _, buf, job_id in iter_all_instances() do
		if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			vim.fn.jobstop(job_id)
		end
		if buf then
			buffer_config.cleanup(buf)
		end
	end

	-- Empty the instances tables
	for mode, _ in pairs(M.instances) do
		M.instances[mode] = {}
	end

	-- Clean up active pointers
	M.active_job_id = nil
	M.active_buf = nil

	-- Reset active state
	M.active_mode = "none"
	M.active_index = 0

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
		index = M.active_index,
		container_running = container_running,
		container_name = container_name,
	}
end

--- Query workmux for the authoritative set of worktree handles.
--- Returns a set table { [handle] = true, ... } on success, or nil on failure.
--- Uses io.popen (synchronous) which is acceptable because workmux list is fast
--- and this runs on the main loop where blocking I/O is already permitted.
local function get_workmux_handles()
	if vim.fn.executable("workmux") ~= 1 then
		return nil
	end
	local pipe = io.popen("workmux list --json 2>/dev/null")
	if not pipe then
		return nil
	end
	local output = pipe:read("*a")
	pipe:close()
	if not output or output == "" then
		return nil
	end
	local decode_ok, worktrees = pcall(vim.json.decode, output)
	if not decode_ok or type(worktrees) ~= "table" then
		log.warn("get_workmux_handles: failed to decode workmux list output")
		return nil
	end
	local handles = {}
	for _, wt in ipairs(worktrees) do
		if type(wt) == "table" and type(wt.handle) == "string" then
			handles[wt.handle] = true
		end
	end
	return handles
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

	-- Prune entries for worktrees that no longer exist according to workmux.
	-- Uses `workmux list --json` as the authoritative source instead of
	-- filesystem checks, which can give false negatives inside containers
	-- or during concurrent startup races.
	-- If workmux is unavailable, pruning is skipped entirely (append-only
	-- fallback) to avoid deleting valid entries we cannot verify.
	local handles = get_workmux_handles()
	if handles then
		for key, _ in pairs(entries) do
			if key ~= worktree_name and not handles[key] then
				entries[key] = nil
			end
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

-- Open the agent fullscreen in the current window with no prompt.
-- Intended for command-line use, e.g.:
--   nvim +AgentFullscreen
--   nvim "+AgentFullscreen claude"
--
-- Sets agent_fullscreen so the BufEnter autocmd in commands.lua
-- reverts to a [file] | [agent] vsplit when the user opens a file.
--
-- When invoked from a `+command` startup argument, vim is still finishing
-- initialization and the UI/PTY isn't fully ready yet; calling termopen
-- synchronously here causes the spawned agent process to exit immediately.
-- Defer the work until vim is fully initialized (matches the pattern used
-- by WorkmuxPrompt, which is dispatched from a VimEnter autocmd).
function M.OpenFullscreen(mode)
	mode = mode or M.default_mode
	log.info("OpenFullscreen: scheduling fullscreen agent start, mode=" .. tostring(mode))
	local function start()
		log.info("OpenFullscreen: starting agent in fullscreen, mode=" .. tostring(mode))
		M.agent_fullscreen = true
		-- idx defaults to 0; fullscreen always operates on the default instance.
		M.Open(mode, nil, "current")
	end

	if vim.v.vim_did_enter == 1 then
		-- Already past startup (e.g. user typed :AgentFullscreen interactively).
		start()
	else
		-- Still in startup (invoked via `nvim +AgentFullscreen ...`). Wait for
		-- VimEnter so the UI/PTY is ready before we call termopen.
		vim.api.nvim_create_autocmd("VimEnter", {
			once = true,
			callback = function()
				-- Small additional defer mirrors WorkmuxPrompt's 100ms delay,
				-- which gives other VimEnter handlers a chance to settle.
				vim.defer_fn(start, 100)
			end,
			desc = "Deferred AgentFullscreen start after VimEnter",
		})
	end
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

	-- Build prompt args based on the agent mode:
	-- opencode uses --prompt <text>, while claude/pi take a positional argument.
	-- shellescape wraps in single quotes, which table.concat in claude.lua joins with spaces.
	-- Use "current" window type so the agent fills the whole viewport on boot;
	-- a BufEnter autocmd will revert it to a vsplit when a file is opened.
	local command_name = parse_mode(M.default_mode)
	local prompt_args
	if command_name == "opencode" then
		prompt_args = { "--prompt", vim.fn.shellescape(prompt_text) }
	else
		-- claude, pi, and others accept the prompt as a positional argument
		prompt_args = { vim.fn.shellescape(prompt_text) }
	end
	M.agent_fullscreen = true
	-- Workmux flow always uses the default instance (idx 0).
	M.Open(M.default_mode, prompt_args, "current")
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
