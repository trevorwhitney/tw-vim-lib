-- Standalone Lua test: asserts that drawer highlighting is stripped from
-- windows edgy no longer owns, and left alone everywhere else.
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local function fail(msg)
	io.stderr:write("FAIL: " .. msg .. "\n")
	os.exit(1)
end

local function eq(expected, actual, msg)
	if expected ~= actual then
		fail(msg .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Minimal vim surface: windows map to buffers, buffers to filetypes, and
-- window-local winhighlight is readable and writable. Records the augroups
-- deleted so the test can assert edgy's per-window re-stamp is torn down.
local function make_vim(state)
	local function opt_table(store)
		return setmetatable({}, {
			__index = function(_, id)
				return setmetatable({}, {
					__index = function(_, name)
						return (store[id] or {})[name]
					end,
					__newindex = function(_, name, value)
						store[id] = store[id] or {}
						store[id][name] = value
					end,
				})
			end,
		})
	end

	return {
		wo = opt_table(state.win_opts),
		bo = opt_table(state.buf_opts),
		schedule = function(fn)
			table.insert(state.scheduled, fn)
		end,
		api = {
			nvim_list_wins = function()
				return state.wins
			end,
			nvim_win_is_valid = function(win)
				return state.win_bufs[win] ~= nil
			end,
			nvim_win_get_buf = function(win)
				return state.win_bufs[win]
			end,
			nvim_set_option_value = function(name, value, opts)
				state.win_opts[opts.win] = state.win_opts[opts.win] or {}
				state.win_opts[opts.win][name] = value
			end,
			nvim_del_augroup_by_name = function(name)
				table.insert(state.deleted_augroups, name)
			end,
			nvim_create_augroup = function(name)
				state.augroup = name
				return 1
			end,
			nvim_create_autocmd = function(events, opts)
				table.insert(state.autocmds, { events = events, opts = opts })
			end,
		},
	}
end

local EDGY_WHL = "WinBar:EdgyWinBar,WinBarNC:EdgyWinBarNC,Normal:EdgyNormal"

-- Fresh module instance bound to a fresh fake vim, so cases cannot leak state.
local function load_module(state, managed)
	package.loaded["tw.agent.edgy_winhl"] = nil
	package.loaded["edgy"] = {
		get_win = function(win)
			return managed[win] and {} or nil
		end,
	}
	_G.vim = make_vim(state)
	return require("tw.agent.edgy_winhl")
end

local function new_state()
	return {
		wins = {},
		win_bufs = {},
		win_opts = {},
		buf_opts = {},
		deleted_augroups = {},
		autocmds = {},
		scheduled = {},
	}
end

-- Run everything vim.schedule() queued, as the event loop would.
local function drain(state)
	local queued = state.scheduled
	state.scheduled = {}
	for _, fn in ipairs(queued) do
		fn()
	end
	return #queued
end

-- strip() removes only edgy's own targets and preserves everything else.
do
	local m = load_module(new_state(), {})

	eq("", m.strip(EDGY_WHL), "strip removes every edgy target")
	eq("", m.strip(""), "strip tolerates an empty winhighlight")
	eq("", m.strip(nil), "strip tolerates a nil winhighlight")
	eq(
		"Normal:MyNormal,SignColumn:MySign",
		m.strip("Normal:MyNormal,WinBar:EdgyWinBar,SignColumn:MySign"),
		"strip keeps highlights another plugin owns"
	)
	eq(
		"Normal:EdgyLike",
		m.strip("Normal:EdgyLike"),
		"strip matches the whole group name, not an Edgy prefix"
	)
end

-- A window edgy has released, now showing an ordinary file, loses the drawer
-- highlighting and edgy's per-window augroup that would otherwise re-stamp it.
do
	local state = new_state()
	state.wins = { 1001 }
	state.win_bufs = { [1001] = 7 }
	state.win_opts = { [1001] = { winhighlight = EDGY_WHL } }
	state.buf_opts = { [7] = { filetype = "lua" } }

	local m = load_module(state, {})
	m.sweep()

	eq("", state.win_opts[1001].winhighlight, "released window loses the drawer highlighting")
	eq(
		"edgy_window_1001",
		state.deleted_augroups[1],
		"released window loses edgy's per-window re-stamp augroup"
	)
end

-- A window edgy still owns keeps its drawer highlighting.
do
	local state = new_state()
	state.wins = { 1002 }
	state.win_bufs = { [1002] = 8 }
	state.win_opts = { [1002] = { winhighlight = EDGY_WHL } }
	state.buf_opts = { [8] = { filetype = "AgentConsole" } }

	local m = load_module(state, { [1002] = true })
	m.sweep()

	eq(EDGY_WHL, state.win_opts[1002].winhighlight, "owned drawer keeps its highlighting")
	eq(0, #state.deleted_augroups, "owned drawer keeps edgy's augroup")
end

-- A drawer buffer is never stripped even while edgy reports no owner, so a
-- transient relayout cannot bleach a live drawer.
do
	local state = new_state()
	state.wins = { 1003, 1004 }
	state.win_bufs = { [1003] = 9, [1004] = 10 }
	state.win_opts = { [1003] = { winhighlight = EDGY_WHL }, [1004] = { winhighlight = EDGY_WHL } }
	state.buf_opts = { [9] = { filetype = "NvimTree" }, [10] = { filetype = "tw-agent-sidebar" } }

	local m = load_module(state, {})
	m.sweep()

	eq(EDGY_WHL, state.win_opts[1003].winhighlight, "NvimTree drawer survives a transient relayout")
	eq(EDGY_WHL, state.win_opts[1004].winhighlight, "agent sidebar survives a transient relayout")
	eq(0, #state.deleted_augroups, "no augroup torn down during a transient relayout")
end

-- An untainted window is left completely alone.
do
	local state = new_state()
	state.wins = { 1005 }
	state.win_bufs = { [1005] = 11 }
	state.win_opts = { [1005] = { winhighlight = "" } }
	state.buf_opts = { [11] = { filetype = "lua" } }

	local m = load_module(state, {})
	m.sweep()

	eq("", state.win_opts[1005].winhighlight, "untainted window is unchanged")
	eq(0, #state.deleted_augroups, "untainted window has no augroup torn down")
end

-- setup() registers a single guarded augroup covering the events that can
-- surface a released drawer window.
do
	local state = new_state()
	local m = load_module(state, {})
	m.setup()

	if #state.autocmds ~= 1 then
		fail("setup must register exactly one autocmd, got " .. #state.autocmds)
	end
	local events = {}
	for _, e in ipairs(state.autocmds[1].events) do
		events[e] = true
	end
	for _, required in ipairs({ "BufWinEnter", "WinEnter", "WinNew", "WinClosed" }) do
		if not events[required] then
			fail("setup must watch " .. required)
		end
	end
	if state.augroup == nil then
		fail("setup must create its own augroup")
	end
end

-- Bursts of events collapse into a single sweep, and the debounce reopens
-- afterwards so later events are not swallowed.
do
	local state = new_state()
	state.wins = { 1006 }
	state.win_bufs = { [1006] = 12 }
	state.win_opts = { [1006] = { winhighlight = EDGY_WHL } }
	state.buf_opts = { [12] = { filetype = "lua" } }

	local m = load_module(state, {})
	m.setup()
	local fire = state.autocmds[1].opts.callback

	fire()
	fire()
	fire()
	eq(1, #state.scheduled, "a burst of events schedules exactly one sweep")
	eq(1, drain(state), "the queued sweep runs")
	eq("", state.win_opts[1006].winhighlight, "the debounced sweep still cleans")

	-- edgy re-stamps the window; the next event must be able to clean it again.
	state.win_opts[1006].winhighlight = EDGY_WHL
	fire()
	eq(1, #state.scheduled, "the debounce reopens after a sweep runs")
	drain(state)
	eq("", state.win_opts[1006].winhighlight, "a later re-stamp is cleaned too")
end

-- Windows on other tabpages are swept, and drawers living there are spared
-- even though edgy's global layout does not report them as owned.
do
	local state = new_state()
	state.wins = { 2001, 2002 }
	state.win_bufs = { [2001] = 21, [2002] = 22 }
	state.win_opts = { [2001] = { winhighlight = EDGY_WHL }, [2002] = { winhighlight = EDGY_WHL } }
	state.buf_opts = { [21] = { filetype = "markdown" }, [22] = { filetype = "NvimTree" } }

	local m = load_module(state, {})
	m.sweep()

	eq("", state.win_opts[2001].winhighlight, "a released window on another tabpage is cleaned")
	eq(EDGY_WHL, state.win_opts[2002].winhighlight, "a drawer on another tabpage is spared")
end

print("ok - edgy_winhl strips released drawer highlighting")
