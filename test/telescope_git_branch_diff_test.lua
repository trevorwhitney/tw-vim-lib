-- Standalone tests for tw.telescope-git-branch-diff.util
-- Run: lua test/telescope_git_branch_diff_test.lua (or via make test-lua)

local H = dofile("test/harness.lua")
local test, eq, eq_list = H.test, H.eq, H.eq_list

vim = vim or { fn = {}, v = {} }

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local util = require("tw.telescope-git-branch-diff.util")

print("telescope-git-branch-diff util tests:")
print()

-- ---------------------------------------------------------------------------
-- git_branch_cmd
-- ---------------------------------------------------------------------------
test("git_branch_cmd lists local + remote refs sorted by committerdate", function()
	eq_list({
		"git",
		"for-each-ref",
		"--format=%(refname:short)",
		"--sort=-committerdate",
		"refs/heads/",
		"refs/remotes/",
	}, util.git_branch_cmd(), "cmd")
end)

-- ---------------------------------------------------------------------------
-- make_entry_maker
-- ---------------------------------------------------------------------------
test("make_entry_maker builds an entry for a local branch", function()
	local e = util.make_entry_maker()("main")
	eq("main", e.value, "value")
	eq("main", e.display, "display")
	eq("main", e.ordinal, "ordinal")
end)

test("make_entry_maker builds an entry for a remote branch", function()
	local e = util.make_entry_maker()("origin/main")
	eq("origin/main", e.value, "value")
end)

test("make_entry_maker returns nil for empty lines", function()
	eq(nil, util.make_entry_maker()(""), "empty string")
	eq(nil, util.make_entry_maker()(nil), "nil")
end)

test("make_entry_maker skips the bare remote pointer", function()
	eq(nil, util.make_entry_maker()("origin"), "bare origin")
end)

-- ---------------------------------------------------------------------------
-- build_diff_command
-- ---------------------------------------------------------------------------
test("build_diff_command opens diffview against the branch", function()
	eq("DiffviewOpen main", util.build_diff_command("main"), "cmd")
	eq("DiffviewOpen origin/main", util.build_diff_command("origin/main"), "cmd")
end)

test("build_diff_command returns nil for nil/empty branch", function()
	eq(nil, util.build_diff_command(nil), "nil")
	eq(nil, util.build_diff_command(""), "empty")
end)

H.finish()
