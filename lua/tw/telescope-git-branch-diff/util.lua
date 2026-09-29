-- Pure(-ish) helpers for the git-branch-diff telescope picker, extracted so
-- they can be unit-tested in plain `lua` without a telescope dependency. The
-- picker wiring lives in lua/tw/telescope-git-branch-diff.lua and requires this
-- module.
local M = {}

--- Build the git command that lists branches (local + remote) newest-first.
--- @return string[]
function M.git_branch_cmd()
	return {
		"git",
		"for-each-ref",
		"--format=%(refname:short)",
		"--sort=-committerdate",
		"refs/heads/",
		"refs/remotes/",
	}
end

--- Parse a branch line into a telescope entry, skipping empties and bare remote
--- HEAD pointers (e.g. a plain "origin" with no branch after it).
--- @return fun(line: string): table|nil
function M.make_entry_maker()
	return function(line)
		if not line or line == "" then
			return nil
		end
		-- A remote name with no "/branch" suffix is the bare remote pointer.
		if not line:find("/") and line:find("origin") then
			return nil
		end
		return {
			value = line,
			display = line,
			ordinal = line,
		}
	end
end

--- Build the DiffviewOpen command for the selected branch.
--- DiffviewOpen <branch> diffs the working tree against that branch, which is
--- the "how does my branch compare to <branch>" view.
--- @param branch string|nil
--- @param current_file_path string|nil
--- @param fnameescape fun(path: string): string
--- @return string|nil
function M.build_diff_command(branch, current_file_path, fnameescape)
	if not branch or branch == "" then
		return nil
	end
	local cmd = "DiffviewOpen " .. branch
	if current_file_path and current_file_path ~= "" then
		cmd = cmd .. " -- " .. fnameescape(current_file_path)
	end
	return cmd
end

return M
