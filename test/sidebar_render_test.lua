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
	},
}

local function load_sidebar()
	package.loaded["tw.agent.sidebar"] = nil
	return require("tw.agent.sidebar")
end

local config = {
	icons = { working = "W", waiting = "A", dead = "D" },
	mode_abbrev = { opencode = "oc", claude = "cl" },
}

print("sidebar render tests:")
print()

test("render_lines emits header then indented description per entry", function()
	local sidebar = load_sidebar()
	local entries = {
		{ mode = "opencode", idx = 0, status = "working", description = "doing x" },
	}
	local lines = sidebar._render_lines(entries, config)
	eq("⌬ Agents", lines[1], "header line 1")
	eq("─────────", lines[2], "header line 2")
	eq("W oc#0  working", lines[3], "header row has no description")
	eq("    doing x", lines[4], "description row is indented 4 spaces")
end)

test("render_lines renders loading and error on the description row", function()
	local sidebar = load_sidebar()
	local entries = {
		{ mode = "opencode", idx = 0, status = "working", description = "loading" },
		{ mode = "claude", idx = 1, status = "waiting", description = "error" },
	}
	local lines = sidebar._render_lines(entries, config)
	eq("    ⋯ loading...", lines[4], "loading on first entry's desc row")
	eq("    ⚠ failed", lines[6], "error on second entry's desc row")
end)

test("render_lines renders nil description as indent-only blank row", function()
	local sidebar = load_sidebar()
	local entries = {
		{ mode = "opencode", idx = 0, status = "working", description = nil },
	}
	local lines = sidebar._render_lines(entries, config)
	eq("    ", lines[4], "nil description renders as indent only")
end)

test("render_lines keeps single-row empty state", function()
	local sidebar = load_sidebar()
	local lines = sidebar._render_lines({}, config)
	eq("(no active sessions)", lines[3], "empty-state row")
	eq(nil, lines[4], "no extra rows when empty")
end)

test("entry_header_row uses a stride of 2", function()
	local sidebar = load_sidebar()
	eq(3, sidebar._entry_header_row(3, 1), "entry 1 header at data_start_line")
	eq(5, sidebar._entry_header_row(3, 2), "entry 2 header two rows down")
	eq(7, sidebar._entry_header_row(3, 3), "entry 3 header four rows down")
end)

test("build_line_to_entry maps both header and description rows", function()
	local sidebar = load_sidebar()
	local entries = { { idx = 0 }, { idx = 1 } }
	local map = sidebar._build_line_to_entry(entries, 3)
	eq(1, map[3], "entry 1 header row")
	eq(1, map[4], "entry 1 description row")
	eq(2, map[5], "entry 2 header row")
	eq(2, map[6], "entry 2 description row")
end)

test("is_header_row is true only on header rows", function()
	local sidebar = load_sidebar()
	eq(true, sidebar._is_header_row(3, 3), "row 3 is a header")
	eq(false, sidebar._is_header_row(3, 4), "row 4 is a description")
	eq(true, sidebar._is_header_row(3, 5), "row 5 is a header")
	eq(false, sidebar._is_header_row(3, 6), "row 6 is a description")
	eq(false, sidebar._is_header_row(3, 1), "rows before data_start_line are not headers")
end)

H.finish()
