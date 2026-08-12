-- Standalone tests for tw.agent.window_picker.
-- Run: lua test/agent_window_picker_test.lua (or via make test-lua)
--
-- Stubs vim so this runs outside Neovim.

-- Per-test mutable state describing the fake windows and input.
local state

local function reset_state()
	state = {
		win_opts = {}, -- win id -> { winbar = ... }
		cmds = {}, -- recorded vim.cmd calls
		getcharstr_result = "",
		getcharstr_error = false,
		getcharstr_calls = 0,
		winbar_at_prompt = {}, -- win id -> winbar value when getcharstr ran
		hl_defs = {}, -- highlight name -> definition
	}
end
reset_state()

vim = {
	wo = setmetatable({}, {
		__index = function(_, win)
			state.win_opts[win] = state.win_opts[win] or {}
			return state.win_opts[win]
		end,
	}),
	cmd = function(c)
		table.insert(state.cmds, c)
	end,
	fn = {
		getcharstr = function()
			state.getcharstr_calls = state.getcharstr_calls + 1
			state.winbar_at_prompt = {}
			for win, opts in pairs(state.win_opts) do
				state.winbar_at_prompt[win] = opts.winbar
			end
			if state.getcharstr_error then
				error("Keyboard interrupt")
			end
			return state.getcharstr_result
		end,
	},
	api = {
		nvim_set_hl = function(_, name, def)
			state.hl_defs[name] = def
		end,
	},
}

package.path = "lua/?.lua;" .. package.path
package.loaded["tw.agent.window_picker"] = nil
local picker = require("tw.agent.window_picker")

local H = dofile("test/harness.lua")
local test, eq, eq_list = H.test, H.eq, H.eq_list

print("agent window_picker tests:")
print()

-- Run one pick against windows 101/102 (winbars preset to edgy-style titles)
-- and return the on_choice result plus a call counter.
local function run_pick(input, opts)
	opts = opts or {}
	reset_state()
	vim.wo[101].winbar = "edgy-title-1"
	vim.wo[102].winbar = "edgy-title-2"
	state.getcharstr_result = input
	state.getcharstr_error = opts.getcharstr_error or false
	local chosen, calls = "never-called", 0
	picker.pick(opts.win_ids or { 101, 102 }, function(win)
		chosen, calls = win, calls + 1
	end)
	return chosen, calls
end

test("labels windows with letters in win_ids order while prompting", function()
	run_pick("\27")
	eq(true, state.winbar_at_prompt[101]:find(" A ", 1, true) ~= nil, "win 101 shows A")
	eq(true, state.winbar_at_prompt[102]:find(" B ", 1, true) ~= nil, "win 102 shows B")
	eq(true, state.winbar_at_prompt[101]:find("TwAgentWindowPicker", 1, true) ~= nil, "letter uses picker highlight")
end)

test("defines the TwAgentWindowPicker highlight as a default", function()
	run_pick("A")
	local def = state.hl_defs["TwAgentWindowPicker"]
	eq(true, def ~= nil, "highlight defined")
	eq(true, def.default, "default=true so user overrides win")
end)

test("issues exactly one redraw and one prompt", function()
	run_pick("A")
	eq_list({ "redraw" }, state.cmds, "vim.cmd calls")
	eq(1, state.getcharstr_calls, "getcharstr count")
end)

test("uppercase letter picks the matching window", function()
	local chosen, calls = run_pick("B")
	eq(102, chosen, "chose second window")
	eq(1, calls, "on_choice called once")
end)

test("lowercase letter picks the matching window", function()
	local chosen = run_pick("a")
	eq(101, chosen, "chose first window")
end)

test("bare Esc cancels", function()
	local chosen, calls = run_pick("\27")
	eq(nil, chosen, "cancelled")
	eq(1, calls, "on_choice called once")
end)

test("multi-byte sequence (arrow key) cancels instead of matching Esc's first byte", function()
	local chosen = run_pick("\27[A")
	eq(nil, chosen, "cancelled")
end)

test("empty input cancels", function()
	local chosen = run_pick("")
	eq(nil, chosen, "cancelled")
end)

test("unassigned letter cancels", function()
	local chosen = run_pick("z")
	eq(nil, chosen, "cancelled")
end)

test("getcharstr error cancels", function()
	local chosen, calls = run_pick("A", { getcharstr_error = true })
	eq(nil, chosen, "cancelled")
	eq(1, calls, "on_choice called once")
end)

test("restores winbars after choice, cancel, and getcharstr error", function()
	local cases = {
		{ label = "choice", input = "A" },
		{ label = "cancel", input = "\27" },
		{ label = "error", input = "A", getcharstr_error = true },
	}
	for _, case in ipairs(cases) do
		run_pick(case.input, { getcharstr_error = case.getcharstr_error })
		eq("edgy-title-1", state.win_opts[101].winbar, case.label .. ": win 101 restored")
		eq("edgy-title-2", state.win_opts[102].winbar, case.label .. ": win 102 restored")
	end
end)

test("empty win_ids cancels without prompting", function()
	local chosen, calls = run_pick("A", { win_ids = {} })
	eq(nil, chosen, "cancelled")
	eq(1, calls, "on_choice called once")
	eq(0, state.getcharstr_calls, "no prompt")
end)

H.finish("agent window_picker tests")
