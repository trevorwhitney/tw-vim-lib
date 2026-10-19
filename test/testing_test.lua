-- Standalone tests for tw.testing.get_test_project_root()
-- Run: lua test/testing_test.lua (or via make test-lua)
--
-- The function picks language-specific marker files by filetype, searches
-- upward for them, and falls back to cwd. We stub vim.bo.filetype,
-- vim.fn.findfile / fnamemodify / getcwd to exercise the branches.

local H = dofile("test/harness.lua")
local test, eq, eq_list = H.test, H.eq, H.eq_list

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

-- Builds a vim stub.
--   filetype: vim.bo.filetype value
--   found:    table mapping a marker name -> the path findfile should return
--             (anything not present returns "" = not found)
--   cwd:      value returned by getcwd()
-- Records the markers findfile was queried with, in order, for assertions.
local function make_vim(filetype, found, cwd)
	found = found or {}
	local queried = {}
	local v = {
		bo = { filetype = filetype },
		fn = {
			findfile = function(marker, _path)
				table.insert(queried, marker)
				return found[marker] or ""
			end,
			fnamemodify = function(p, mods)
				-- Only ":h" (head/dirname) is used by the function.
				if mods == ":h" then
					return (p:gsub("/[^/]+$", ""))
				end
				return p
			end,
			getcwd = function()
				return cwd or "/default/cwd"
			end,
		},
	}
	return v, queried
end

local function load_testing()
	package.loaded["tw.testing"] = nil
	return require("tw.testing")
end

print("testing.get_test_project_root tests:")
print()

-- ---------------------------------------------------------------------------
-- Filetype -> marker selection (assert the markers queried)
-- ---------------------------------------------------------------------------
local ft_markers = {
	javascript = { "package.json" },
	typescript = { "package.json" },
	typescriptreact = { "package.json" },
	javascriptreact = { "package.json" },
	go = { "go.mod" },
	ruby = { "Gemfile", ".ruby-version" },
	python = { "setup.py", "pyproject.toml", "requirements.txt", "Pipfile" },
	rust = { "Cargo.toml" },
	java = { "build.gradle", "build.gradle.kts", "pom.xml" },
	groovy = { "build.gradle", "build.gradle.kts", "pom.xml" },
	kotlin = { "build.gradle", "build.gradle.kts", "pom.xml" },
}

for ft, expected_markers in pairs(ft_markers) do
	test("filetype '" .. ft .. "' searches its markers then falls back to cwd", function()
		local v, queried = make_vim(ft, {}, "/proj/cwd")
		vim = v
		local m = load_testing()
		-- No markers found -> returns cwd.
		eq("/proj/cwd", m.get_test_project_root(), "root")
		-- All expected markers were queried, in order.
		eq(#expected_markers, #queried, "queried count for " .. ft)
		for i, marker in ipairs(expected_markers) do
			eq(marker, queried[i], "marker[" .. i .. "] for " .. ft)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Marker found -> returns its directory
-- ---------------------------------------------------------------------------
test("returns dirname of a found marker (go.mod)", function()
	vim = make_vim("go", { ["go.mod"] = "../sub/go.mod" }, "/cwd")
	local m = load_testing()
	eq("../sub", m.get_test_project_root(), "root")
end)

test("returns first matching marker's dir (ruby Gemfile before .ruby-version)", function()
	vim = make_vim("ruby", { ["Gemfile"] = "proj/Gemfile", [".ruby-version"] = "proj/.ruby-version" }, "/cwd")
	local m = load_testing()
	eq("proj", m.get_test_project_root(), "root")
end)

test("falls through to a later marker when earlier ones are absent (python)", function()
	-- Only the 3rd marker (requirements.txt) exists.
	vim = make_vim("python", { ["requirements.txt"] = "app/requirements.txt" }, "/cwd")
	local m = load_testing()
	eq("app", m.get_test_project_root(), "root")
end)

-- ---------------------------------------------------------------------------
-- Unknown filetype -> no markers -> cwd
-- ---------------------------------------------------------------------------
test("unknown filetype searches no markers and returns cwd", function()
	local v, queried = make_vim("markdown", {}, "/home/cwd")
	vim = v
	local m = load_testing()
	eq("/home/cwd", m.get_test_project_root(), "root")
	eq(0, #queried, "no markers queried")
end)

test("empty filetype returns cwd", function()
	local v, queried = make_vim("", {}, "/x/y")
	vim = v
	local m = load_testing()
	eq("/x/y", m.get_test_project_root(), "root")
	eq(0, #queried, "no markers queried")
end)

-- ---------------------------------------------------------------------------
-- M.dispatch: closes/reopens the agent sidebar around `:Dispatch <cmd>` so a
-- fixed-height sidebar view doesn't collide with edgy's layout pass when
-- Dispatch's quickfix-fallback window shrinks the available rows.
-- ---------------------------------------------------------------------------
local function fake_sidebar(initially_open)
	local calls = {}
	local open = initially_open
	return {
		is_open = function()
			return open
		end,
		open = function()
			open = true
			table.insert(calls, "open")
		end,
		close = function()
			open = false
			table.insert(calls, "close")
		end,
	}, calls
end

test("dispatch closes and reopens the sidebar when it was open", function()
	local sidebar, calls = fake_sidebar(true)
	package.loaded["tw.agent.sidebar"] = sidebar
	local cmds = {}
	vim = {
		cmd = function(c)
			table.insert(cmds, c)
		end,
	}
	local m = load_testing()
	m.dispatch("GoTest")
	eq_list({ "close", "open" }, calls, "sidebar calls")
	eq_list({ "Dispatch GoTest" }, cmds, "vim.cmd calls")
	package.loaded["tw.agent.sidebar"] = nil
end)

test("dispatch leaves the sidebar alone when it was already closed", function()
	local sidebar, calls = fake_sidebar(false)
	package.loaded["tw.agent.sidebar"] = sidebar
	vim = {
		cmd = function() end,
	}
	local m = load_testing()
	m.dispatch("GoTest")
	eq_list({}, calls, "sidebar calls")
	package.loaded["tw.agent.sidebar"] = nil
end)

test("dispatch reopens the sidebar even if :Dispatch errors, then reraises", function()
	local sidebar, calls = fake_sidebar(true)
	package.loaded["tw.agent.sidebar"] = sidebar
	vim = {
		cmd = function()
			error("boom")
		end,
	}
	local m = load_testing()
	local ok, err = pcall(m.dispatch, "GoTest")
	eq(false, ok, "dispatch should reraise")
	eq(true, tostring(err):find("boom") ~= nil, "error message preserved")
	eq_list({ "close", "open" }, calls, "sidebar still reopened")
	package.loaded["tw.agent.sidebar"] = nil
end)

H.finish()
