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

-- Real rendering replaces this stub.
function M.refresh() end

return M
