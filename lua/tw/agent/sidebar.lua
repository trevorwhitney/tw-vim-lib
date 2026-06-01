local M = {}

local DEFAULTS = {
	enabled = true,
	width = 20,
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
	keymap = "<leader>cv",
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
	user_cursor_idx = nil,
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
		return
	end
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

local function set_window_options(win)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	vim.wo[win].winfixwidth = true
	vim.wo[win].list = false
	vim.wo[win].foldcolumn = "0"
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
	state.win = open_window(state.buf, state.config.position, state.config.width)
	set_window_options(state.win)
	-- Static placeholder; replaced by refresh() once rendering is in place.
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "⌬ Agents", "─────────", "(loading)" })
	vim.bo[state.buf].modifiable = false
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

function M.toggle()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close()
	else
		M.open()
	end
end

-- The four local agent modes shown in the sidebar; docker variants are
-- intentionally excluded.
local LOCAL_MODES = { "opencode", "claude", "codex", "pi" }

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
			if inst and inst.buf and inst.job_id then
				local s = status.detect({
					mode = mode,
					idx = idx,
					buf = inst.buf,
					job_id = inst.job_id,
				})
				if s ~= "dead" or state.config.show_dead then
					table.insert(entries, {
						mode = mode,
						idx = idx,
						status = s,
						buf = inst.buf,
						is_active = (mode == agent.active_mode and idx == agent.active_index),
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
		table.insert(lines, string.format("%s %s#%d  %s", icon, mode_short, e.idx, e.status))
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

function M.refresh()
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		return
	end
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	local entries = collect_entries()
	local lines = render_lines(entries)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	state.entries = entries
	state.line_to_entry = build_line_to_entry(entries)
	apply_highlights(state.buf, entries)
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
