local M = {}

local DEFAULTS = {
	enabled = true,
	width = 45,
	position = "left", -- "left" or "right"
	refresh_ms = 1000,
	icons = {
		working = "", -- nf-fa-cog (\uf013)
		waiting = "", -- nf-fa-comment (\uf075)
		dead = "", -- nf-fa-times-circle (\uf057)
	},
	mode_abbrev = {
		opencode = "oc",
		claude = "cl",
		codex = "cx",
		pi = "pi",
	},
	show_dead = false,
}

-- Internal state, exposed via M._state() for tests.
local state = {
	win = nil,
	buf = nil,
	timer = nil,
	ns = nil,
	entries = {},
	line_to_entry = {},
	data_start_line = 3,
	config = nil,
}

function M._state()
	return state
end

local function merge_defaults(opts)
	local merged = vim.deepcopy(DEFAULTS)
	for k, v in pairs(opts or {}) do
		if type(v) == "table" and type(merged[k]) == "table" then
			merged[k] = vim.tbl_extend("force", merged[k], v)
		else
			merged[k] = v
		end
	end
	return merged
end

function M.setup(opts)
	state.config = merge_defaults(opts or {})
	state.ns = vim.api.nvim_create_namespace("tw_agent_sidebar")
	if state.config.enabled == false then
		-- Clear the augroup in case a previous setup() registered handlers.
		pcall(vim.api.nvim_del_augroup_by_name, "tw_agent_sidebar")
		return
	end

	-- Clear=true makes repeated setup() calls idempotent.
	local augroup = vim.api.nvim_create_augroup("tw_agent_sidebar", { clear = true })
	vim.api.nvim_create_autocmd("TermClose", {
		group = augroup,
		pattern = "agent://*",
		callback = function(args)
			pcall(function()
				local status = require("tw.agent.status")
				if status and status.invalidate then
					status.invalidate(args.buf)
				end
			end)
			pcall(M.refresh)
		end,
		desc = "Refresh sidebar on agent terminal close",
	})
end

local function create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "tw-agent-sidebar"
	vim.bo[buf].modifiable = false
	pcall(vim.api.nvim_buf_set_name, buf, "tw-agent-sidebar")
	return buf
end

local function open_window(buf, position, width)
	-- nvim_open_win's split mode (0.10+) takes an existing buffer directly,
	-- so no orphan/scratch buffer is created the way :vsplit would.
	return vim.api.nvim_open_win(buf, true, {
		split = position,
		win = -1,
		width = width,
	})
end

local function set_window_options(win, stacked)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	vim.wo[win].winfixwidth = true
	vim.wo[win].list = false
	vim.wo[win].foldcolumn = "0"
	-- Stacked under NERDTree: pin the height so window resizing elsewhere
	-- doesn't grow/shrink the agents pane.
	if stacked then
		vim.wo[win].winfixheight = true
	end
end

-- Fixed height (in lines) of the agents window when stacked below NERDTree:
-- 2 header lines + 10 agent rows (indices 0-9) + 1 padding line.
local _STACKED_HEIGHT = 13

-- Filetypes of the file-explorer plugins we stack the agents pane beneath.
-- Matched case-insensitively so "NvimTree" and "nvimtree" both qualify.
local FILE_TREE_FILETYPES = {
	nvimtree = true, -- nvim-tree.lua
	nerdtree = true, -- NERDTree
	["neo-tree"] = true, -- neo-tree.nvim
}

-- Return the first window in the CURRENT tabpage whose buffer is a known
-- file-explorer (nvim-tree, NERDTree, neo-tree), or nil. Uses
-- nvim_tabpage_list_wins (not nvim_list_wins, which spans all tabpages) so a
-- file tree in another tab is ignored.
local function find_nerdtree_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.bo[buf].filetype
		if ft and FILE_TREE_FILETYPES[ft:lower()] then
			return win
		end
	end
	return nil
end

function M._find_nerdtree_win()
	return find_nerdtree_win()
end

function M._stacked_height()
	return _STACKED_HEIGHT
end

function M.close()
	if state.timer then
		pcall(state.timer.stop, state.timer)
		pcall(state.timer.close, state.timer)
		state.timer = nil
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	state.buf = nil
end

-- The four local agent modes shown in the sidebar; docker variants are
-- intentionally excluded.
local LOCAL_MODES = { "opencode", "claude", "codex", "pi" }

-- Helper functions for navigation and keymaps.
local function find_next_data_row(direction)
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		return nil
	end
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local row = cursor[1]
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	-- Scan in direction until we land on a data row; wraps at top/bottom.
	for _ = 1, line_count do
		row = row + direction
		if row < 1 then
			row = line_count
		end
		if row > line_count then
			row = 1
		end
		if state.line_to_entry[row] then
			return row
		end
	end
	return nil
end

local function move_cursor(direction)
	local row = find_next_data_row(direction)
	if row then
		vim.api.nvim_win_set_cursor(state.win, { row, 0 })
	end
end

local function first_data_row()
	for r = state.data_start_line, vim.api.nvim_buf_line_count(state.buf) do
		if state.line_to_entry[r] then
			return r
		end
	end
	return nil
end

local function last_data_row()
	local last = nil
	for r = state.data_start_line, vim.api.nvim_buf_line_count(state.buf) do
		if state.line_to_entry[r] then
			last = r
		end
	end
	return last
end

local function set_buffer_keymaps(buf)
	local map = function(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
	end
	map("j", function()
		move_cursor(1)
	end, "Sidebar: next session")
	map("k", function()
		move_cursor(-1)
	end, "Sidebar: previous session")
	map("<CR>", function()
		M._activate_under_cursor()
	end, "Sidebar: activate session")
	map("o", function()
		M._activate_under_cursor()
	end, "Sidebar: activate session")
	map("q", function()
		M.close()
	end, "Sidebar: close")
	map("<Esc>", function()
		M.close()
	end, "Sidebar: close")
	map("r", function()
		M.refresh()
	end, "Sidebar: force refresh")
	map("gg", function()
		local r = first_data_row()
		if r then
			vim.api.nvim_win_set_cursor(state.win, { r, 0 })
		end
	end, "Sidebar: first session")
	map("G", function()
		local r = last_data_row()
		if r then
			vim.api.nvim_win_set_cursor(state.win, { r, 0 })
		end
	end, "Sidebar: last session")
end

function M.open()
	if not state.config or state.config.enabled == false then
		return
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		return
	end
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		state.buf = create_buffer()
	end
	local nt_win = find_nerdtree_win()
	-- Only stack below NERDTree when the sidebar is configured on the left;
	-- a right-positioned sidebar must honour its own position.
	local stacked = nt_win ~= nil and state.config.position == "left"
	if stacked then
		-- Stack the agents window below NERDTree, forming one left drawer.
		-- No width is passed: the split inherits NERDTree's column width.
		local ok, win = pcall(vim.api.nvim_open_win, state.buf, true, {
			split = "below",
			win = nt_win,
			height = _STACKED_HEIGHT,
		})
		if ok then
			state.win = win
		else
			-- NERDTree window vanished mid-open; fall back to full height.
			local log_ok, log = pcall(require, "tw.log")
			if log_ok and log and log.warn then
				log.warn("sidebar stacked open failed, falling back: " .. tostring(win))
			end
			stacked = false
			state.win = open_window(state.buf, state.config.position, state.config.width)
		end
	else
		state.win = open_window(state.buf, state.config.position, state.config.width)
	end
	set_window_options(state.win, stacked)

	set_buffer_keymaps(state.buf)

	-- BufWinLeave catches the user closing the sidebar via :q. Schedule the
	-- close call so we don't try to delete a window inside its own event.
	vim.api.nvim_create_autocmd("BufWinLeave", {
		buffer = state.buf,
		once = true,
		callback = function()
			vim.schedule(function()
				M.close()
			end)
		end,
	})

	-- Initial render so the user doesn't see a blank window.
	M.refresh()

	-- Periodic refresh.
	state.timer = vim.uv.new_timer()
	if state.timer then
		state.timer:start(
			state.config.refresh_ms,
			state.config.refresh_ms,
			vim.schedule_wrap(function()
				local ok, err = pcall(M.refresh)
				if not ok then
					local log_ok, log = pcall(require, "tw.log")
					if log_ok and log and log.warn then
						log.warn("sidebar refresh failed: " .. tostring(err))
					end
				end
			end)
		)
	end
end

function M.toggle()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close()
	else
		M.open()
	end
end

-- Highlight groups applied to each status. Defined later in the module
-- (define_highlights) so they exist before any caller calls refresh().
local STATUS_HL = {
	working = "TwAgentSidebarWorking",
	waiting = "TwAgentSidebarWaiting",
	dead = "TwAgentSidebarDead",
}

local function collect_entries()
	local agent = require("tw.agent")
	local status = require("tw.agent.status")
	local entries = {}
	for _, mode in ipairs(LOCAL_MODES) do
		local instances = agent.instances[mode] or {}
		local indices = {}
		for idx, _ in pairs(instances) do
			table.insert(indices, idx)
		end
		table.sort(indices)
		for _, idx in ipairs(indices) do
			local inst = instances[idx]
			if inst and inst.buf and vim.api.nvim_buf_is_valid(inst.buf) and inst.job_id then
				local s = status.detect({
					mode = mode,
					idx = idx,
					buf = inst.buf,
					job_id = inst.job_id,
				})
				if s ~= "dead" or state.config.show_dead then
					local desc = nil
					local ok_desc, description = pcall(require, "tw.agent.description")
					if ok_desc and description and description.get then
						desc = description.get(inst.buf)
					end

					table.insert(entries, {
						mode = mode,
						idx = idx,
						status = s,
						buf = inst.buf,
						is_active = (mode == agent.active_mode and idx == agent.active_index),
						description = desc,
					})
				end
			end
		end
	end
	return entries
end

local function render_lines(entries)
	local lines = { "⌬ Agents", "─────────" }
	if #entries == 0 then
		table.insert(lines, "(no active sessions)")
		return lines
	end
	local icons = state.config.icons
	local abbrev = state.config.mode_abbrev
	for _, e in ipairs(entries) do
		local icon = icons[e.status] or "?"
		local mode_short = abbrev[e.mode] or e.mode
		local desc_str = ""
		if e.description == "loading" then
			desc_str = "  ⋯ loading..."
		elseif e.description == "error" then
			desc_str = "  ⚠ failed"
		elseif e.description and e.description ~= "" then
			desc_str = "  " .. e.description
		end
		table.insert(lines, string.format("%s %s#%d  %s%s", icon, mode_short, e.idx, e.status, desc_str))
	end
	return lines
end

local function apply_highlights(buf, entries)
	vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
	local header_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	vim.api.nvim_buf_set_extmark(buf, state.ns, 0, 0, {
		end_col = #header_line,
		hl_group = "TwAgentSidebarHeader",
	})
	for i, e in ipairs(entries) do
		local row = state.data_start_line - 1 + (i - 1)
		local hl = STATUS_HL[e.status] or "Comment"
		vim.api.nvim_buf_set_extmark(buf, state.ns, row, 0, {
			end_row = row + 1,
			end_col = 0,
			hl_group = hl,
			hl_eol = false,
		})
		if e.is_active then
			vim.api.nvim_buf_set_extmark(buf, state.ns, row, 0, {
				line_hl_group = "TwAgentSidebarActive",
			})
		end
	end
end

local function build_line_to_entry(entries)
	local map = {}
	for i = 1, #entries do
		map[state.data_start_line + (i - 1)] = i
	end
	return map
end

function M._activate_under_cursor()
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local row = cursor[1]
	local entry_idx = state.line_to_entry[row]
	if not entry_idx then
		return
	end
	local entry = state.entries[entry_idx]
	if not entry then
		return
	end
	local ok, agent = pcall(require, "tw.agent")
	if not ok then
		return
	end
	agent.Open(entry.mode, nil, "vsplit", entry.idx)
end

function M.refresh()
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		return
	end
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end

	-- Only preserve cursor when the user is actually focused on the sidebar
	-- window; otherwise the default positioning logic applies.
	local cursor_target = nil
	if vim.api.nvim_get_current_win() == state.win then
		local cursor = vim.api.nvim_win_get_cursor(state.win)
		local row = cursor[1]
		local prev_idx = state.line_to_entry[row]
		if prev_idx and state.entries[prev_idx] then
			cursor_target = {
				mode = state.entries[prev_idx].mode,
				idx = state.entries[prev_idx].idx,
			}
		end
	end

	local entries = collect_entries()
	local lines = render_lines(entries)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	state.entries = entries
	state.line_to_entry = build_line_to_entry(entries)
	apply_highlights(state.buf, entries)

	-- Restore cursor to the same (mode, idx) if it still exists.
	if cursor_target then
		for i, e in ipairs(entries) do
			if e.mode == cursor_target.mode and e.idx == cursor_target.idx then
				vim.api.nvim_win_set_cursor(state.win, { state.data_start_line + (i - 1), 0 })
				return
			end
		end
	end

	-- Default positioning: the active entry, then the first entry.
	for i, e in ipairs(entries) do
		if e.is_active then
			vim.api.nvim_win_set_cursor(state.win, { state.data_start_line + (i - 1), 0 })
			return
		end
	end
	if #entries > 0 then
		vim.api.nvim_win_set_cursor(state.win, { state.data_start_line, 0 })
	end
end

local function define_highlights()
	local groups = {
		TwAgentSidebarHeader = "Title",
		TwAgentSidebarWorking = "String",
		TwAgentSidebarWaiting = "WarningMsg",
		TwAgentSidebarDead = "ErrorMsg",
		TwAgentSidebarActive = "Visual",
	}
	for name, link in pairs(groups) do
		vim.api.nvim_set_hl(0, name, { link = link, default = true })
	end
end

-- Define highlight groups at module load so they're available even
-- before setup() is called.
define_highlights()

return M
