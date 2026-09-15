local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

_G.vim = {
	deepcopy = function(t)
		local function copy(x)
			if type(x) ~= "table" then
				return x
			end
			local r = {}
			for k, v in pairs(x) do
				r[k] = copy(v)
			end
			return r
		end
		return copy(t)
	end,
	tbl_extend = function(_behavior, a, b)
		local r = {}
		for k, v in pairs(a) do
			r[k] = v
		end
		for k, v in pairs(b) do
			r[k] = v
		end
		return r
	end,
	api = {
		nvim_create_namespace = function()
			return 1
		end,
		nvim_set_hl = function() end,
		nvim_create_augroup = function()
			return 1
		end,
		nvim_create_autocmd = function()
			return 1
		end,
		nvim_win_is_valid = function()
			return true
		end,
	},
}

local function load_sidebar()
	package.loaded["tw.agent.sidebar"] = nil
	return require("tw.agent.sidebar")
end

local config = {
	icons = { running = "R", dead = "D" },
	mode_abbrev = { opencode = "oc", claude = "cl" },
}

test("each terminal occupies exactly one row", function()
	local sidebar = load_sidebar()
	local entries = {
		{ mode = "opencode", idx = 0, status = "running" },
		{ mode = "claude", idx = 1, status = "dead" },
	}
	local lines = sidebar._render_lines(entries, config)
	eq("R oc#0  running", lines[3])
	eq("D cl#1  dead", lines[4])
	eq(nil, lines[5])
	local map = sidebar._build_line_to_entry(entries, 3)
	eq(1, map[3])
	eq(2, map[4])
	eq(nil, map[5])
end)

test("empty sidebar has a single placeholder", function()
	local lines = load_sidebar()._render_lines({}, config)
	eq("(no active sessions)", lines[3])
	eq(nil, lines[4])
end)

H.finish()
