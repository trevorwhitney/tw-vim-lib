-- Standalone tests for tw.agent.gf (gf-in-editor-pane).
-- Run: lua test/agent_gf_test.lua (or via make test-lua)
--
-- Stubs vim so this runs outside Neovim.

-- Per-test mutable state describing the fake window layout.
local state

local function reset_state()
	state = {
		wins = {}, -- list of win ids in tabpage order
		win_valid = {}, -- win id -> bool
		win_config = {}, -- win id -> config table
		win_buf = {}, -- win id -> buf id
		buf_ft = {}, -- buf id -> filetype
		current_win = nil,
		commands = {}, -- recorded vim.cmd calls
	}
end
reset_state()

vim = {
	api = {
		nvim_tabpage_list_wins = function()
			return state.wins
		end,
		nvim_win_is_valid = function(win)
			return state.win_valid[win] == true
		end,
		nvim_win_get_config = function(win)
			return state.win_config[win] or {}
		end,
		nvim_win_get_buf = function(win)
			return state.win_buf[win]
		end,
		nvim_set_current_win = function(win)
			state.current_win = win
		end,
	},
	bo = setmetatable({}, {
		__index = function(_, buf)
			return { filetype = state.buf_ft[buf] or "" }
		end,
	}),
	cmd = function(c)
		table.insert(state.commands, c)
	end,
	fn = {
		fnameescape = function(p)
			return p
		end,
		expand = function()
			return state.cfile or ""
		end,
		findfile = function()
			return state.findfile_result or ""
		end,
	},
}

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
package.loaded["tw.agent.gf"] = nil
local gf = require("tw.agent.gf")

local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

print("agent gf tests:")
print()

-- Register a window in the fake layout.
local function add_win(win, buf, ft, opts)
	opts = opts or {}
	table.insert(state.wins, win)
	state.win_valid[win] = opts.invalid ~= true
	state.win_buf[win] = buf
	state.buf_ft[buf] = ft
	state.win_config[win] = opts.config or {}
end

test("find_editor_win returns an ordinary editor window", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	add_win(11, 101, "lua")
	eq(11, gf.find_editor_win())
end)

test("find_editor_win skips edgy sidebar filetypes", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	add_win(11, 101, "NvimTree")
	add_win(12, 102, "tw-agent-sidebar")
	eq(nil, gf.find_editor_win())
end)

test("find_editor_win skips floating windows", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	add_win(11, 101, "lua", { config = { relative = "editor" } })
	eq(nil, gf.find_editor_win())
end)

test("find_editor_win returns first editor window in tab order", function()
	reset_state()
	add_win(11, 101, "go")
	add_win(12, 102, "lua")
	eq(11, gf.find_editor_win())
end)

test("open_in_editor_pane reuses an existing editor window", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	add_win(11, 101, "lua")
	gf.open_in_editor_pane("/path/to/file.lua")
	eq(11, state.current_win)
	eq("edit /path/to/file.lua", state.commands[1])
end)

test("open_in_editor_pane creates a left split when no editor window exists", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	gf.open_in_editor_pane("/path/to/file.lua")
	eq(nil, state.current_win)
	eq("vertical topleft split /path/to/file.lua", state.commands[1])
end)

test("gf resolves <cfile> and opens it in the editor pane", function()
	reset_state()
	add_win(10, 100, "AgentConsole")
	add_win(11, 101, "lua")
	state.cfile = "lua/tw/agent/gf.lua"
	state.findfile_result = "lua/tw/agent/gf.lua"
	gf.gf()
	eq(11, state.current_win)
	eq("edit lua/tw/agent/gf.lua", state.commands[1])
end)

test("gf does nothing when <cfile> is empty", function()
	reset_state()
	add_win(11, 101, "lua")
	state.cfile = ""
	gf.gf()
	eq(0, #state.commands)
end)

H.finish()
