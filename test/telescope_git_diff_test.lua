-- Standalone tests for tw.telescope-git-diff.util
-- Run: lua test/telescope_git_diff_test.lua (or via make test-lua)
--
-- The helpers were extracted into a telescope-free util module precisely so
-- they can be exercised here in plain `lua`. has_upstream touches
-- vim.fn.systemlist / vim.v.shell_error, which we stub per-test.

local H = dofile("test/harness.lua")
local test, eq, eq_list = H.test, H.eq, H.eq_list

-- Minimal vim stub; individual tests override vim.fn / vim.v as needed.
vim = vim or { fn = {}, v = {} }

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local util = require("tw.telescope-git-diff.util")

print("telescope-git-diff util tests:")
print()

-- ---------------------------------------------------------------------------
-- git_log_cmd
-- ---------------------------------------------------------------------------
test("git_log_cmd(true) returns capped --max-count log", function()
	eq_list({ "git", "log", "--oneline", "--max-count=500" }, util.git_log_cmd(true), "cmd")
end)

test("git_log_cmd(false) returns unpushed range", function()
	eq_list({ "git", "log", "--oneline", "@{upstream}..HEAD" }, util.git_log_cmd(false), "cmd")
end)

-- ---------------------------------------------------------------------------
-- picker_title (all three states; no_upstream wins over show_all)
-- ---------------------------------------------------------------------------
test("picker_title no_upstream returns 'all -- no upstream'", function()
	eq("Diff (all -- no upstream)", util.picker_title(true, true), "title")
	-- no_upstream takes precedence even when show_all is false
	eq("Diff (all -- no upstream)", util.picker_title(false, true), "title")
end)

test("picker_title show_all (with upstream) returns 'all'", function()
	eq("Diff (all)", util.picker_title(true, false), "title")
end)

test("picker_title unpushed returns 'unpushed'", function()
	eq("Diff (unpushed)", util.picker_title(false, false), "title")
end)

-- ---------------------------------------------------------------------------
-- make_entry_maker (sha parsing, index increment, nil on non-sha)
-- ---------------------------------------------------------------------------
test("make_entry_maker parses sha and increments index", function()
	local counter = { n = 0 }
	local maker = util.make_entry_maker(counter)

	local e1 = maker("abc1234 first commit")
	eq("abc1234", e1.value, "value")
	eq("abc1234 first commit", e1.display, "display")
	eq("abc1234 first commit", e1.ordinal, "ordinal")
	eq(1, e1.index, "index")
	eq(1, counter.n, "counter")

	local e2 = maker("deadbeef second commit")
	eq("deadbeef", e2.value, "value")
	eq(2, e2.index, "index")
	eq(2, counter.n, "counter")
end)

test("make_entry_maker returns nil on a non-sha line (no increment)", function()
	local counter = { n = 5 }
	local maker = util.make_entry_maker(counter)
	-- A line that does not start with a hex sha.
	eq(nil, maker("  (no commits)"), "entry")
	eq(5, counter.n, "counter unchanged")
end)

test("make_entry_maker only matches leading hex chars as sha", function()
	local counter = { n = 0 }
	local maker = util.make_entry_maker(counter)
	-- "fix:" -> leading "f" is hex; sha capture is the leading hex run "f".
	local e = maker("fix: typo")
	eq("f", e.value, "value (leading hex run)")
	-- A line starting with a non-hex char returns nil.
	eq(nil, maker("zztop not a sha"), "non-hex leading char")
	eq(1, counter.n, "counter only advanced for the matched line")
end)

-- ---------------------------------------------------------------------------
-- build_diff_command (selection sort + cmd assembly)
-- ---------------------------------------------------------------------------
test("build_diff_command nil/empty selections returns nil", function()
	eq(nil, util.build_diff_command(nil, nil), "nil selections")
	eq(nil, util.build_diff_command({}, nil), "empty selections")
end)

test("build_diff_command single selection diffs against parent (~1)", function()
	local sel = { { value = "abc1234", index = 1 } }
	eq("DiffviewOpen abc1234~1", util.build_diff_command(sel, nil), "cmd")
end)

test("build_diff_command single selection with current file", function()
	local sel = { { value = "abc1234", index = 1 } }
	eq(
		"DiffviewOpen abc1234~1 -- /path/to/file.lua",
		util.build_diff_command(sel, "/path/to/file.lua"),
		"cmd"
	)
end)

test("build_diff_command two selections orders older~1..newer (higher index = older)", function()
	-- selection order as picked is newer-first; helper must sort to older..newer.
	local sel = {
		{ value = "newsha", index = 1 }, -- nearer top of log = newer
		{ value = "oldsha", index = 5 }, -- further down log = older
	}
	eq("DiffviewOpen oldsha~1..newsha", util.build_diff_command(sel, nil), "cmd")
end)

test("build_diff_command two selections regardless of input order", function()
	-- Same commits, opposite input order: result must be identical.
	local sel = {
		{ value = "oldsha", index = 5 },
		{ value = "newsha", index = 1 },
	}
	eq("DiffviewOpen oldsha~1..newsha", util.build_diff_command(sel, nil), "cmd")
end)

test("build_diff_command does not mutate caller's selections table", function()
	local sel = {
		{ value = "newsha", index = 1 },
		{ value = "oldsha", index = 5 },
	}
	util.build_diff_command(sel, nil)
	-- Original order preserved.
	eq("newsha", sel[1].value, "sel[1] unchanged")
	eq("oldsha", sel[2].value, "sel[2] unchanged")
end)

test("build_diff_command applies fnameescape to current file", function()
	local sel = { { value = "abc1234", index = 1 } }
	local escaped = util.build_diff_command(sel, "weird name.lua", function(p)
		return (p:gsub(" ", "\\ "))
	end)
	eq("DiffviewOpen abc1234~1 -- weird\\ name.lua", escaped, "cmd")
end)

-- ---------------------------------------------------------------------------
-- has_upstream (stub vim.fn.systemlist + vim.v.shell_error)
-- ---------------------------------------------------------------------------
local function with_upstream_stub(shell_error, result, fn)
	local old_fn, old_v = vim.fn, vim.v
	vim.fn = { systemlist = function(_)
		return result
	end }
	vim.v = { shell_error = shell_error }
	local ok, err = pcall(fn)
	vim.fn, vim.v = old_fn, old_v
	if not ok then
		error(err)
	end
end

test("has_upstream true when shell_error 0 and branch returned", function()
	with_upstream_stub(0, { "origin/main" }, function()
		eq(true, util.has_upstream(), "has_upstream")
	end)
end)

test("has_upstream false when shell_error non-zero", function()
	with_upstream_stub(128, {}, function()
		eq(false, util.has_upstream(), "has_upstream")
	end)
end)

test("has_upstream false when no output lines", function()
	with_upstream_stub(0, {}, function()
		eq(false, util.has_upstream(), "has_upstream")
	end)
end)

test("has_upstream false when first line is empty", function()
	with_upstream_stub(0, { "" }, function()
		eq(false, util.has_upstream(), "has_upstream")
	end)
end)

H.finish()
