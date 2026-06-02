local M = {}

local CACHE_MS = 500
-- An agent terminal that has produced output in the last 30 seconds is
-- considered "working"; older than that, it's assumed the turn is done and
-- the agent is "waiting" for the user. Threshold is generous to accommodate
-- agents that pause to think before producing visible output. Used only for
-- non-opencode modes (claude/codex/pi), which lack a reliable TUI marker.
local WORKING_STALE_MS = 30000

-- Patterns matched against the last 20 lines of terminal buffer content,
-- after ANSI stripping.
--
-- The OpenCode TUI shows an interrupt hint ("esc interrupt" / "esc again to
-- interrupt", and during provider retries) below the input box ONLY while it
-- is generating. When the turn finishes and it's idle/waiting for the user,
-- that hint disappears. So the presence of the word "interrupt" is the single
-- reliable "working" signal; its absence means the agent is "waiting". The
-- trailing word "interrupt" is a hardcoded literal in the TUI (only the "esc"
-- key prefix is user-configurable), so it's stable to match.
local OPENCODE_WORKING = {
	"interrupt",
}

-- Per-buffer cache: { [buf] = { status, checked_at = ms } }.
-- checked_at uses vim.uv.now() (monotonic ms) for the same reason
-- buffer-config records last_change_at that way: elapsed-time
-- comparisons need monotonic, millisecond-resolution time.
local cache = {}

local function strip_ansi(s)
	-- CSI: ESC [ <params/intermediates> <final-byte>
	-- params: digits, semicolons, colons, ?, >, < (private modifiers)
	-- intermediates: spaces, !, ", #, $, %, &, ', (, ), *, +, ,, -, ., /
	-- final byte: any letter or @[\]^_`{|}~
	s = s:gsub("\27%[[%d;:%?%>%<]*[ -/]*[A-Za-z@%[\\%]^_`{|}~]", "")
	-- OSC: ESC ] <anything except BEL or ESC> <terminator>
	-- Terminators: BEL (\7) or ESC \ (ST)
	s = s:gsub("\27%][^\7\27]*\7", "")
	s = s:gsub("\27%][^\27]*\27\\", "")
	-- Two-byte ESC sequences: ESC <single letter or = > >
	s = s:gsub("\27[=>%(%)#%*+%-./]", "")
	return s
end

local function any_match(text, patterns)
	for _, p in ipairs(patterns) do
		if text:find(p) then
			return true
		end
	end
	return false
end

local function detect_opencode(buf)
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, -20, -1, false)
	if not ok or not lines then
		-- Can't read the buffer; report "waiting" rather than silently
		-- reporting "working" for something we can't see.
		return "waiting"
	end
	local joined = strip_ansi(table.concat(lines, "\n"))
	-- The interrupt hint is shown only while generating. If it's present the
	-- agent is working; otherwise the turn is done and it's waiting for input.
	if any_match(joined, OPENCODE_WORKING) then
		return "working"
	end
	return "waiting"
end

local function is_dead(instance)
	if not instance.job_id then
		return true
	end
	local ok, result = pcall(vim.fn.jobwait, { instance.job_id }, 0)
	if not ok or not result then
		return true
	end
	return result[1] ~= -1
end

local function detect_timing(buf)
	local ok, buffer_config = pcall(require, "tw.agent.buffer-config")
	if not ok or not buffer_config or not buffer_config.buffer_states then
		return "waiting"
	end
	local state = buffer_config.buffer_states[buf]
	if not state or not state.last_change_at then
		return "waiting"
	end
	if (vim.uv.now() - state.last_change_at) < WORKING_STALE_MS then
		return "working"
	end
	return "waiting"
end

function M.detect(instance)
	if not instance or not instance.buf then
		return "dead"
	end
	local buf = instance.buf

	local cached = cache[buf]
	if cached and (vim.uv.now() - cached.checked_at) < CACHE_MS then
		return cached.status
	end

	local status
	if is_dead(instance) then
		status = "dead"
	elseif instance.mode == "opencode" then
		status = detect_opencode(buf)
	else
		status = detect_timing(buf)
	end

	cache[buf] = { status = status, checked_at = vim.uv.now() }
	return status
end

function M.invalidate(buf)
	cache[buf] = nil
end

function M.reset()
	cache = {}
end

-- Automatically clear per-buffer state when a buffer is wiped. Prevents
-- stale entries from accumulating if callers forget to invalidate.
local augroup = vim.api.nvim_create_augroup("tw_agent_status_cleanup", { clear = true })
vim.api.nvim_create_autocmd("BufWipeout", {
	group = augroup,
	callback = function(args)
		cache[args.buf] = nil
	end,
	desc = "Drop status cache for wiped buffers",
})

return M
