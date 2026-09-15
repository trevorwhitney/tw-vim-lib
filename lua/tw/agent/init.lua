local M = {}

local claude = require("tw.agent.claude")
local terminal = require("tw.agent.terminal")
local util = require("tw.agent.util")
local log = require("tw.log")
local commands = require("tw.agent.commands")
local buffer_config = require("tw.agent.buffer-config")
local default_args = {}

-- Notify the sidebar that something in the instance/active state changed.
-- pcall-guarded so the sidebar module is fully optional.
local function notify_sidebar_refresh()
	pcall(function()
		require("tw.agent.sidebar").refresh()
	end)
end

local function notify_sidebar_close()
	pcall(function()
		require("tw.agent.sidebar").close()
	end)
end

-- Expose log module globally for claude.lua to use
_G.claude_log = log
-- Single source of truth for the default agent.
-- Change this value to switch every default (Open, Toggle, WorkmuxPrompt, etc.).
M.default_mode = "opencode"
M.active_mode = "none" -- currently visible mode, or "none" when no agent is shown
M.active_index = 0 -- idx of the visible/last-shown instance

-- Active buffer/job_id points to the currently visible buffer
M.active_buf = nil
M.active_job_id = nil

M.saved_updatetime = nil

-- Fullscreen state: when true, the agent occupies the full viewport
-- and will revert to a vsplit when a non-terminal buffer is opened.
M.agent_fullscreen = false

-- Context directories configuration (per-session only)
M.context_directories = {} -- Table of paths to mount

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
	pi = {},
	opencode = {},
	claude = {},
	codex = {},
}

local function get_instance(mode, idx)
	idx = idx or 0
	M.instances[mode] = M.instances[mode] or {}
	return M.instances[mode][idx]
end

local function set_instance(mode, idx, buf, job_id)
	idx = idx or 0
	M.instances[mode] = M.instances[mode] or {}
	M.instances[mode][idx] = { buf = buf, job_id = job_id, mode = mode }
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
				if inst then
					return mode, idx, inst.buf, inst.job_id
				end
			else
				mi, idx_keys = mi + 1, nil
			end
		end
		return nil
	end
end

-- Stable internal API for the plenary spec suite. Not for external use.
M._get_instance = get_instance
M._set_instance = set_instance
M._clear_instance = clear_instance
M._iter_all_instances = iter_all_instances

-- Find the plugin installation path
local function _get_plugin_root()
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
		notify_sidebar_refresh()
		if M.active_mode == mode and M.active_index == idx then
			M.active_mode = "none"
			M.active_index = 0
			M.active_buf = nil
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

local function start_new_agent_job(args, window_type, mode, idx, launch_options)
	mode = mode or M.default_mode
	idx = idx or 0
	launch_options = launch_options or {}
	log.info("Attempting to start new job in " .. mode .. " mode")

	-- Create a copy of args to avoid mutating the original (especially default_args)
	args = args and vim.deepcopy(args) or {}

	-- For opencode, always add the project root path
	if mode == "opencode" then
		log.debug("Processing opencode command")
		local git_root = util.get_git_root()
		log.debug("Git root: " .. tostring(git_root))
		if git_root then
			log.debug("Initial args count: " .. #args)
			-- shellescape the path: claude.command joins args with spaces into a
			-- single string for termopen, so a root containing spaces (e.g. a
			-- Google Drive path) would word-split into extra positionals and make
			-- opencode reject the arguments. Matches the --prompt escaping below.
			local project_path = vim.fn.shellescape(git_root)
			log.debug("Project path: " .. project_path)

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

	log.debug("Local mode enabled for " .. mode)
	local final_args = vim.tbl_extend("force", {}, default_args)
	if args and #args > 0 then
		log.debug("Extending final_args with " .. #args .. " args")
		vim.list_extend(final_args, args)
	end
	log.debug("Final args before command: " .. vim.inspect(final_args))
	command = claude.command(final_args, mode, M.context_directories, launch_options.automatic_permissions ~= false)
	if not command then
		log.error("Failed to build command for " .. mode, true)
		return
	end
	log.debug("Using command: " .. command)

	log.info("Starting " .. mode .. " with command: " .. command)

	terminal.open_window(window_type)
	buf = vim.api.nvim_get_current_buf()
	job_id = vim.fn.termopen(command, {
		on_exit = OnExit(mode, idx),
		-- TODO: make this configurable
		env = {
			-- vrnsh records PATH before the packaged Neovim adds editor tooling.
			PATH = vim.env.VRNSH_ORIGINAL_PATH,
			-- Unset TMUX/STY so child processes emit plain OSC 52 clipboard
			-- sequences instead of wrapping them in tmux DCS passthrough.
			-- Neovim's terminal emulator handles plain OSC 52 natively but
			-- cannot parse tmux DCS wrappers, causing raw base64 to leak
			-- onto the display.
			TMUX = "",
			STY = "",
			-- Stable panel identifier for external integrations.
			TW_AGENT_SLOT = mode .. "#" .. idx,
		},
	})
	vim.bo[buf].bufhidden = "hide"

	-- Configure the buffer with scrollback and resize handling
	buffer_config.setup_buffer(buf, M.buffer_config, mode)

	if M.agent_fullscreen then
		vim.b[buf].edgy_disable = true
	end

	-- Store via the multi-instance helper
	set_instance(mode, idx, buf, job_id)
	-- Set the agent:// buffer name for identification (must happen BEFORE
	-- any consumer reads the name)
	pcall(vim.api.nvim_buf_set_name, buf, string.format("agent://%s#%d", mode, idx))
	M._apply_agent_updatetime()

	-- Update active state
	M.active_mode = mode
	M.active_index = idx
	M.active_buf = buf
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

local function confirmOpenAndDo(callback, args, window_type, target_mode, target_idx)
	args = args or default_args
	window_type = window_type or "vsplit"

	-- Route to a specific (mode, idx) instance: spawn it if its job is dead
	-- (deferring callback ~2500ms so the agent can initialize), re-show its
	-- buffer if hidden, update active state, then run callback.
	local inst = get_instance(target_mode, target_idx)
	local alive = inst
		and inst.buf
		and vim.api.nvim_buf_is_valid(inst.buf)
		and inst.job_id
		and vim.fn.jobwait({ inst.job_id }, 0)[1] == -1
	if not alive then
		M.Open(target_mode, args, window_type, target_idx)
		vim.defer_fn(function()
			if callback then
				callback()
			end
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
		terminal.open_buffer_in_new_window(window_type, inst.buf)
	end
	M.active_mode, M.active_index = target_mode, target_idx
	M.active_buf, M.active_job_id = inst.buf, inst.job_id
	if callback then
		callback()
	end
end

function M.Open(mode, args, window_type, idx, launch_options)
	mode = mode or M.default_mode
	args = args or default_args
	window_type = window_type or "vsplit"
	idx = idx or 0

	local inst = get_instance(mode, idx)
	local buf, job_id
	if inst then
		buf, job_id = inst.buf, inst.job_id
	end

	local job_is_running = job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1

	if buf and vim.api.nvim_buf_is_valid(buf) and job_is_running then
		terminal.open_or_reuse_terminal_buffer(buf, window_type)
		M.active_mode = mode
		M.active_index = idx
		M.active_buf = buf
		M.active_job_id = job_id
	else
		if buf and not job_is_running then
			terminal.close_terminal_buffer(buf, job_id)
			clear_instance(mode, idx)
		end
		start_new_agent_job(args, window_type, mode, idx, launch_options)
	end
	notify_sidebar_refresh()
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

	if not target_mode then
		return false
	end

	local inst = get_instance(target_mode, target_idx)
	if inst and inst.buf then
		terminal.close_terminal_buffer(inst.buf, inst.job_id)
	end
	clear_instance(target_mode, target_idx)
	if M.active_mode == target_mode and M.active_index == target_idx then
		M.active_mode = "none"
		M.active_index = 0
		M.active_buf = nil
		M.active_job_id = nil
	end
	M.Open(target_mode, nil, "vsplit", target_idx)
	return true
end

function M.Toggle(mode, args, window_type, idx)
	mode = mode or M.default_mode
	args = args or default_args
	window_type = window_type or "vsplit"
	idx = idx or 0

	local inst = get_instance(mode, idx)
	local buf, job_id
	if inst then
		buf, job_id = inst.buf, inst.job_id
	end

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
			local tabpage = vim.api.nvim_win_get_tabpage(visible_win)
			if #vim.api.nvim_tabpage_list_wins(tabpage) > 1 then
				vim.api.nvim_win_close(visible_win, false)
			else
				vim.api.nvim_win_call(visible_win, function()
					vim.cmd("enew")
				end)
			end
			if M.active_mode == mode and M.active_index == idx then
				M.active_mode = "none"
				M.active_index = 0
				M.active_buf = nil
				M.active_job_id = nil
			end
		else
			terminal.open_buffer_in_new_window(window_type, buf)
			M.active_mode = mode
			M.active_index = idx
			M.active_buf = buf
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

-- Windows in the current tabpage showing an agent terminal (AgentConsole).
local function agent_console_wins()
	local wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.bo[buf].filetype == "AgentConsole" then
				wins[#wins + 1] = win
			end
		end
	end
	return wins
end

-- Parse "agent://<mode>#<idx>" from a buffer name into mode, idx. The same
-- pattern is duplicated in edgy_config.lua, which stays vim/agent-free at load
-- time; keep both in sync if the agent buffer naming changes.
local function parse_agent_buf_name(name)
	local mode, idx = tostring(name):match("agent://(%w+)#(%d+)")
	if mode and idx then
		return mode, tonumber(idx)
	end
	return nil, nil
end

-- Window in the current tabpage showing agent <mode>#<idx>, or nil.
local function agent_win_for(mode, idx)
	for _, win in ipairs(agent_console_wins()) do
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
		local m, i = parse_agent_buf_name(name)
		if m == mode and i == idx then
			return win
		end
	end
	return nil
end

-- Visible agent windows as { win, mode, idx } entries. A window counts as
-- visible when it is in the current tabpage showing a parseable
-- agent://mode#idx buffer AND edgy does not report its pane as collapsed.
-- edgy's hide() collapses a pane without closing its window, so the
-- filetype filter alone would count collapsed panes as visible. Windows
-- unknown to edgy (plain splits, edgy absent) count as visible.
local function visible_agent_wins()
	local edgy_ok, edgy = pcall(require, "edgy")
	local get_win = (edgy_ok and edgy.get_win) or nil
	local out = {}
	for _, win in ipairs(agent_console_wins()) do
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
		local mode, idx = parse_agent_buf_name(name)
		if mode then
			local collapsed = false
			if get_win then
				local ok, ewin = pcall(get_win, win)
				if ok and ewin and ewin.visible == false then
					collapsed = true
				end
			end
			if not collapsed then
				out[#out + 1] = { win = win, mode = mode, idx = idx }
			end
		end
	end
	return out
end

-- Recorded instances with a running job, as { mode, idx } entries in
-- iter_all_instances order (modes and indices sorted). Dead-but-recorded
-- instances (job exited, not yet cleared) are excluded.
local function alive_instances()
	local out = {}
	for mode, idx, _, job_id in iter_all_instances() do
		if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			out[#out + 1] = { mode = mode, idx = idx }
		end
	end
	return out
end

-- Stable internal API for the plenary spec suite. Not for external use.
M._visible_agent_wins = visible_agent_wins
M._alive_instances = alive_instances

-- Resolve the send target and report it via on_target(mode, idx). on_target
-- runs exactly once on success and never runs when the user cancels a
-- picker. Selection only: spawning and showing are confirmOpenAndDo's job.
-- count == 0: one visible agent window wins; several prompt via the winbar
--             letter picker; none falls back to alive instances (a single
--             one is used directly, several prompt via vim.ui.select, none
--             targets default_mode#0).
-- count 1-9:  (active_mode || default_mode, count)
-- count > 9:  notify and drop
local function resolve_send_target(count, on_target)
	if count > 9 then
		vim.notify(string.format("Agent instance index must be 0-9 (got %d)", count), vim.log.levels.WARN)
		return
	end

	if count > 0 then
		-- explicit ternary: literal "none" is truthy in Lua, so plain
		-- `M.active_mode or M.default_mode` would not fall through.
		local mode = (M.active_mode ~= "none") and M.active_mode or M.default_mode
		on_target(mode, count)
		return
	end

	local visible = visible_agent_wins()
	if #visible == 1 then
		on_target(visible[1].mode, visible[1].idx)
		return
	end
	if #visible > 1 then
		local wins, by_win = {}, {}
		for _, entry in ipairs(visible) do
			wins[#wins + 1] = entry.win
			by_win[entry.win] = entry
		end
		require("tw.agent.window_picker").pick(wins, function(win)
			local chosen = win and by_win[win]
			if chosen then
				on_target(chosen.mode, chosen.idx)
			end
		end)
		return
	end

	local alive = alive_instances()
	if #alive == 0 then
		on_target(M.default_mode, 0)
		return
	end
	if #alive == 1 then
		on_target(alive[1].mode, alive[1].idx)
		return
	end
	vim.ui.select(alive, {
		prompt = "Send to agent:",
		format_item = function(item)
			return string.format("%s#%d", item.mode, item.idx)
		end,
	}, function(choice)
		if choice then
			on_target(choice.mode, choice.idx)
		end
	end)
end

M._resolve_send_target = resolve_send_target

-- Collapse an agent edgy pane. count is passed in directly so this is testable
-- without a read-only vim.v.count. With count 0 it hides the current pane; with
-- count N it hides index N of the current pane's mode (when that pane is shown).
function M._collapse_pane_explicit(current_win, count)
	if count == 0 then
		if current_win and current_win.hide then
			current_win:hide()
		end
		return
	end
	local mode
	if current_win and current_win.win and vim.api.nvim_win_is_valid(current_win.win) then
		local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(current_win.win))
		mode = parse_agent_buf_name(name)
	end
	if not mode then
		return
	end
	local target = agent_win_for(mode, count)
	if not target then
		return
	end
	local ok, edgy = pcall(require, "edgy")
	if ok and edgy.get_win then
		local ewin = edgy.get_win(target)
		if ewin and ewin.hide then
			ewin:hide()
		end
	end
end

-- Entry point for the edgy buffer-local <leader>q keymap. Reads vim.v.count
-- then delegates: no count hides the current pane, N hides index N of its mode.
-- count 0 means "no count" here (hide current), unlike the drawer toggle where
-- a typed 0 closes the whole drawer.
function M.CollapsePane(current_win)
	M._collapse_pane_explicit(current_win, vim.v.count)
end

-- Close the whole right agent drawer (all stacked AgentConsole panes). Prefers
-- edgy's edgebar close; falls back to closing the windows directly. The whole
-- drawer closing deactivates whatever agent was active, so active state is
-- always cleared.
function M.CloseDrawer()
	local wins = agent_console_wins()
	if #wins == 0 then
		return false
	end
	M.active_mode = "none"
	M.active_index = 0
	M.active_buf = nil
	M.active_job_id = nil
	local ok = pcall(function()
		require("edgy").close("right")
	end)
	if not ok then
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				if #vim.api.nvim_tabpage_list_wins(0) > 1 then
					pcall(vim.api.nvim_win_close, win, false)
				else
					vim.api.nvim_win_call(win, function()
						vim.cmd("enew")
					end)
				end
			end
		end
	end
	return true
end

-- Explicit-count entry point used by tests and by _toggle_with_count.
-- count is passed in directly so callers don't need to manipulate the
-- read-only vim.v.count.
function M._toggle_with_count_explicit(mode, count, visual)
	local idx = visual and 0 or count
	if idx > 9 then
		vim.notify(string.format("Agent instance index must be 0-9 (got %d)", idx), vim.log.levels.WARN)
		return
	end
	if not visual and count == 0 and #agent_console_wins() > 0 then
		M.CloseDrawer()
		return
	end
	M.Toggle(mode, nil, "vsplit", idx)
end

-- Keymap entry point. Reads vim.v.count then delegates.
function M._toggle_with_count(mode, visual)
	M._toggle_with_count_explicit(mode, vim.v.count, visual)
end

--- Cycle through alive sessions of default_mode.
--- direction: 1 for next, -1 for previous.
function M.CycleSession(direction)
	local mode = M.default_mode
	local tbl = M.instances[mode] or {}

	-- Collect indices of alive instances
	local indices = {}
	for idx, inst in pairs(tbl) do
		local alive = inst
			and inst.buf
			and vim.api.nvim_buf_is_valid(inst.buf)
			and inst.job_id
			and vim.fn.jobwait({ inst.job_id }, 0)[1] == -1
		if alive then
			table.insert(indices, idx)
		end
	end
	table.sort(indices)

	if #indices == 0 then
		vim.notify("No " .. mode .. " sessions running", vim.log.levels.INFO)
		return
	end

	-- Find current position in sorted list
	local current_idx = (M.active_mode == mode) and M.active_index or -1
	local pos = nil
	for i, idx in ipairs(indices) do
		if idx == current_idx then
			pos = i
			break
		end
	end

	-- Calculate next position (wrapping)
	local next_pos
	if pos then
		next_pos = ((pos - 1 + direction) % #indices) + 1
	else
		-- Not currently on a session of this mode; jump to first or last
		next_pos = (direction == 1) and 1 or #indices
	end

	local target_idx = indices[next_pos]
	M.Open(mode, nil, "vsplit", target_idx)
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

-- Internal dispatcher: resolves the target via resolve_send_target (which may
-- prompt and may drop the send on cancel), ensures the target instance is
-- alive and visible via confirmOpenAndDo, then runs the named send function's
-- logic with an explicit job_id (no reliance on M.active_job_id).
--
-- Send payloads (references, commands, file lists) must be fully built by the
-- caller BEFORE this runs: resolution can prompt, so nothing here or in the
-- callback may read live editor state (marks, cursor, current buffer).
--
-- Exposed as M._send_with_count so tests and keymap wrappers can call it
-- with an explicit count (vim.v.count is read-only and can't be set from
-- Lua, so tests pass count directly).
function M._send_with_count(fn_name, count, ...)
	local extra = { ... }
	resolve_send_target(count, function(mode, idx)
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
					if submit_after then
						submit(job_id)
					end
				end, 500)
			elseif fn_name == "SendText" then
				local args = extra[1]
				local submit_after = extra[2] or false
				send(job_id, args)
				if submit_after then
					submit(job_id)
				end
			elseif fn_name == "SendSelection" then
				-- precomputed reference text passed in via extra[1]
				send(job_id, extra[1])
			elseif fn_name == "SendSymbol" then
				send(job_id, extra[1]) -- precomputed reference
			elseif fn_name == "SendFile" then
				send(job_id, extra[1]) -- precomputed reference
			elseif fn_name == "SendOpenBuffers" then
				-- Three-line context message; submit after
				send(job_id, extra[1])
				submit(job_id)
			else
				log.warn("Unknown send function: " .. tostring(fn_name))
			end
		end, nil, "vsplit", mode, idx)
	end)
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
	local count = vim.v.count -- Snapshot BEFORE any normal! commands clobber it
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
	local end_line = vim.fn.line("'>")
	vim.cmd("normal! \027")

	local reference
	if start_line == end_line then
		reference = "@" .. rel_path .. ":" .. start_line .. " "
	else
		reference = "@" .. rel_path .. ":" .. start_line .. "-" .. end_line .. " "
	end

	M._send_with_count("SendSelection", count, reference)
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
				desc = "Toggle Claude",
			},
			{
				"<leader>cx",
				function()
					require("tw.agent").Toggle("codex")
				end,
				desc = "Toggle Codex",
			},
			{
				"<leader>co",
				function()
					local m = vim.fn.mode()
					local is_visual = m == "v" or m == "V" or m == "\22"
					require("tw.agent")._toggle_with_count("opencode", is_visual)
				end,
				desc = "Toggle OpenCode (count = instance index, 0 = default)",
			},
			{
				"<leader>]",
				function()
					local m = vim.fn.mode()
					local is_visual = m == "v" or m == "V" or m == "\22"
					require("tw.agent")._toggle_with_count("opencode", is_visual)
				end,
				desc = "Toggle OpenCode (count = instance index, 0 = default)",
			},
			{
				"<leader>cp",
				function()
					local m = vim.fn.mode()
					local is_visual = m == "v" or m == "V" or m == "\22"
					require("tw.agent")._toggle_with_count("pi", is_visual)
				end,
				desc = "Toggle Pi (count = instance index, 0 = default)",
			},
		},
		{
			mode = { "n" },
			{
				"]g",
				function()
					require("tw.agent").CycleSession(1)
				end,
				desc = "Next Agent Session",
				nowait = true,
				remap = false,
			},
			{
				"[g",
				function()
					require("tw.agent").CycleSession(-1)
				end,
				desc = "Previous Agent Session",
				nowait = true,
				remap = false,
			},
			{
				"<leader>cv",
				function()
					local ok, sidebar = pcall(require, "tw.agent.sidebar")
					if ok and sidebar and sidebar.toggle then
						sidebar.toggle()
					end
				end,
				desc = "Toggle agent session sidebar",
			},
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

-- Shorten updatetime while any agent terminal is open. Called directly from
-- start_new_agent_job after the buffer is renamed to agent://...
-- (Doing this via TermOpen / BufWinEnter autocmds is unreliable because
-- those events fire before nvim_buf_set_name has been called.)
M.AGENT_UPDATETIME = 100 -- ms; matches the original optimization value
M.saved_updatetime = nil

function M._apply_agent_updatetime()
	if M.saved_updatetime == nil then
		M.saved_updatetime = vim.o.updatetime
		vim.o.updatetime = M.AGENT_UPDATETIME
	end
end

function M._restore_agent_updatetime_if_no_agents()
	for _, _, _, job_id in iter_all_instances() do
		if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			return -- at least one agent still alive
		end
	end
	if M.saved_updatetime ~= nil then
		vim.o.updatetime = M.saved_updatetime
		M.saved_updatetime = nil
	end
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

	if M._refresh_timer then
		M._refresh_timer:stop()
		M._refresh_timer:close()
		M._refresh_timer = nil
	end
	notify_sidebar_close()
end

-- Get status for statusline integration
function M.get_status()
	return {
		mode = M.active_mode,
		index = M.active_index,
	}
end

local function normalize_extra_args(extra)
	if type(extra) == "string" then
		extra = vim.trim(extra)
		if extra == "" then
			return nil
		end
		return { extra }
	elseif type(extra) == "table" and #extra > 0 then
		return vim.deepcopy(extra)
	end
	return nil
end

-- Open the agent fullscreen in the current window with no prompt.
-- Intended for command-line use, e.g.:
--   nvim +AgentFullscreen
--   nvim "+AgentFullscreen claude"
--   nvim "+AgentFullscreen opencode --prompt 'this is a test'"
--
-- extra_args (string or list) is forwarded to the agent binary as-is; see
-- normalize_extra_args for the escaping contract.
--
-- Sets agent_fullscreen so the BufEnter autocmd in commands.lua
-- reverts to a [file] | [agent] vsplit when the user opens a file.
--
-- When invoked from a `+command` startup argument, vim is still finishing
-- initialization and the UI/PTY isn't fully ready yet; calling termopen
-- synchronously here causes the spawned agent process to exit immediately.
-- Defer the work until vim is fully initialized (matches the pattern used
-- by WorkmuxPrompt, which is dispatched from a VimEnter autocmd).
function M.OpenFullscreen(mode, extra_args)
	mode = mode or M.default_mode
	local args = normalize_extra_args(extra_args)
	log.info(
		"OpenFullscreen: scheduling fullscreen agent start, mode=" .. tostring(mode) .. ", args=" .. vim.inspect(args)
	)
	local function start()
		log.info("OpenFullscreen: starting agent in fullscreen, mode=" .. tostring(mode))
		M.agent_fullscreen = true
		vim.schedule(function()
			require("tw.plugin-events").emit_agent_started()
		end)
		-- idx defaults to 0; fullscreen always operates on the default instance.
		M.Open(mode, args, "current", 0, { automatic_permissions = false })
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

	-- Clean up all prompt files so they aren't re-sent on restart
	for _, f in ipairs(prompt_files) do
		vim.fn.delete(f)
	end

	-- Build prompt args based on the agent mode:
	-- opencode uses --prompt <text>, while claude/pi take a positional argument.
	-- shellescape wraps in single quotes, which table.concat in claude.lua joins with spaces.
	-- Use "current" window type so the agent fills the whole viewport on boot;
	-- a BufEnter autocmd will revert it to a vsplit when a file is opened.
	local command_name = M.default_mode
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

	-- Configure buffer settings
	if opts.buffer_config then
		M.buffer_config = vim.tbl_extend("force", M.buffer_config, opts.buffer_config)
	end
	buffer_config.setup(M.buffer_config)

	-- Configure logging
	if opts.log_level then
		log.set_level(opts.log_level)
	end
	require("tw.plugin-events").on_very_lazy(configureClaudeKeymap)

	-- Sidebar
	local sidebar_ok, sidebar_mod = pcall(require, "tw.agent.sidebar")
	if sidebar_ok and sidebar_mod and sidebar_mod.setup then
		sidebar_mod.setup(opts.sidebar or {})
	end

	-- Drawer (unified file-tree + agent sidebar), toggled by <leader>\.
	local drawer_ok, drawer_mod = pcall(require, "tw.agent.drawer")
	if drawer_ok and drawer_mod and drawer_mod.setup then
		drawer_mod.setup(opts.drawer or {})
	end

	-- Batch review comments (optional; guarded so it can't break startup).
	local comments_ok, comments_mod = pcall(require, "tw.agent.comments")
	if comments_ok and comments_mod and comments_mod.setup then
		comments_mod.setup(opts.comments or {})
	end

	-- Setup autocmds and user commands
	commands.setup_autocmds(M)
	commands.setup_user_commands(M)
end

return M
