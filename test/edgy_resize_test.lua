-- Standalone Lua test: asserts a mouse-dragged edgebar keeps its new size,
-- and that edgy's own resizing is never mistaken for a drag.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function fail(msg)
	io.stderr:write("FAIL: " .. msg .. "\n")
	os.exit(1)
end

local function eq(expected, actual, msg)
	if expected ~= actual then
		fail(msg .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Minimal vim surface: window-local variables and options, plus the window
-- geometry the module reads back after a resize.
local function make_vim(state)
	local function per_win(store)
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
		o = state.o,
		w = per_win(state.win_vars),
		wo = per_win(state.win_opts),
		v = { event = {} },
		api = {
			nvim_win_is_valid = function(win)
				return state.win_size[win] ~= nil
			end,
			nvim_win_get_width = function(win)
				return state.win_size[win].width
			end,
			nvim_win_get_height = function(win)
				return state.win_size[win].height
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

-- Fresh module instance bound to a fresh fake vim and a fresh fake edgy.
local function load_module(state)
	package.loaded["tw.agent.edgy_resize"] = nil
	package.loaded["edgy"] = {
		get_win = function(win)
			return state.windows[win]
		end,
	}
	package.loaded["edgy.animate"] = {
		is_active = function()
			return state.animating == true
		end,
	}
	_G.vim = make_vim(state)
	return require("tw.agent.edgy_resize")
end

-- One vertical (left/right) edgebar holding `sizes` windows. Each entry is
-- { win = id, target = what edgy wants, actual = what the window really is }.
local function new_state(entries, opts)
	opts = opts or {}
	local state = {
		o = { columns = opts.columns or 200, lines = opts.lines or 50 },
		win_vars = {},
		win_opts = {},
		win_size = {},
		windows = {},
		autocmds = {},
		animating = false,
	}

	local edgebar = { vertical = opts.vertical ~= false, wins = {} }
	local dim = edgebar.vertical and "width" or "height"
	local other = edgebar.vertical and "height" or "width"
	local fixed = edgebar.vertical and "winfixwidth" or "winfixheight"

	for _, entry in ipairs(entries) do
		local window = { win = entry.win, view = { edgebar = edgebar } }
		window[dim] = entry.target
		table.insert(edgebar.wins, window)
		state.windows[entry.win] = window
		state.win_size[entry.win] = { [dim] = entry.actual, [other] = 20 }
		state.win_opts[entry.win] = { [fixed] = opts.winfix ~= false }
	end

	state.edgebar = edgebar
	return state
end

local function ids(entries)
	local out = {}
	for _, e in ipairs(entries) do
		out[#out + 1] = e.win
	end
	return out
end

-- A drag widens every window sharing the edgebar, so the new width is recorded
-- on all of them: edgy takes the widest as the bar's width.
do
	local entries = { { win = 1, target = 40, actual = 62 }, { win = 2, target = 40, actual = 62 } }
	local state = new_state(entries)
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(62, state.win_vars[1].edgy_width, "dragged window records its new width")
	eq(62, state.win_vars[2].edgy_width, "the window stacked beside it records the same width")
end

-- Narrowing is recorded the same way; nothing floors it back to edgy's default.
do
	local entries = { { win = 1, target = 40, actual = 18 }, { win = 2, target = 40, actual = 18 } }
	local state = new_state(entries)
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(18, state.win_vars[1].edgy_width, "a narrowed bar keeps the narrower width")
end

-- edgy at rest: the window is already the size edgy wants, so there is nothing
-- to adopt and no override is pinned.
do
	local entries = { { win = 1, target = 40, actual = 40 } }
	local state = new_state(entries)
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(nil, state.win_vars[1] and state.win_vars[1].edgy_width, "a settled edgebar is left alone")
end

-- Mid-animation sizes are edgy's own, not the user's.
do
	local entries = { { win = 1, target = 40, actual = 33 } }
	local state = new_state(entries)
	state.animating = true
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(nil, state.win_vars[1] and state.win_vars[1].edgy_width, "an animation frame is not a drag")
end

-- Without winfixwidth the shared dimension moves whenever any other window
-- opens or closes, so a difference cannot be attributed to the user.
do
	local entries = { { win = 1, target = 40, actual = 55 } }
	local state = new_state(entries, { winfix = false })
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(nil, state.win_vars[1] and state.win_vars[1].edgy_width, "an unpinned dimension is not a drag")
end

-- A terminal too narrow to honour the bar's width shrinks it past winfixwidth.
-- Adopting that would keep the bar narrow after the terminal grows back.
do
	local entries = { { win = 1, target = 40, actual = 38 } }
	local state = new_state(entries, { columns = 40 })
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(nil, state.win_vars[1] and state.win_vars[1].edgy_width, "a squeezed bar is not a drag")
end

-- Windows edgy does not own are ignored.
do
	local entries = { { win = 1, target = 40, actual = 40 } }
	local state = new_state(entries)
	local m = load_module(state)

	m.adopt({ 99 })

	eq(nil, state.win_vars[99] and state.win_vars[99].edgy_width, "a plain window is never touched")
end

-- Horizontal edgebars are driven by height, and winfixheight pins it.
do
	local entries = { { win = 1, target = 10, actual = 22 } }
	local state = new_state(entries, { vertical = false })
	local m = load_module(state)

	m.adopt(ids(entries))

	eq(22, state.win_vars[1].edgy_height, "a dragged bottom bar records its new height")
end

-- setup() registers a single WinResized autocmd in its own augroup.
do
	local state = new_state({ { win = 1, target = 40, actual = 40 } })
	local m = load_module(state)
	m.setup()

	eq(1, #state.autocmds, "setup registers exactly one autocmd")
	eq("WinResized", state.autocmds[1].events, "setup watches WinResized")
	if state.augroup == nil then
		fail("setup must create its own augroup")
	end
end

print("ok - edgy_resize keeps a dragged edgebar at its new size")
