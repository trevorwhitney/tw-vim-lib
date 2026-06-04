-- Pure(-ish) helpers for the git-diff telescope picker, extracted so they can
-- be unit-tested in plain `lua` without a telescope dependency. The picker
-- wiring lives in lua/tw/telescope-git-diff.lua and requires this module.
local M = {}

--- Check if an upstream branch exists for the current branch.
--- Depends on `vim.fn.systemlist` / `vim.v.shell_error` (stubbable in tests).
--- @return boolean
function M.has_upstream()
	local result = vim.fn.systemlist("git rev-parse --abbrev-ref @{upstream} 2>/dev/null")
	return vim.v.shell_error == 0 and #result > 0 and result[1] ~= ""
end

--- Build the git log command for the given mode.
--- @param show_all boolean Whether to show all commits or just unpushed
--- @return string[]
function M.git_log_cmd(show_all)
	if show_all then
		-- Cap at 500 to keep the picker responsive on large repos
		return { "git", "log", "--oneline", "--max-count=500" }
	else
		return { "git", "log", "--oneline", "@{upstream}..HEAD" }
	end
end

--- Build the prompt title for the current picker state.
--- @param show_all boolean
--- @param no_upstream boolean
--- @return string
function M.picker_title(show_all, no_upstream)
	if no_upstream then
		return "Diff (all -- no upstream)"
	elseif show_all then
		return "Diff (all)"
	else
		return "Diff (unpushed)"
	end
end

--- Parse a git log --oneline line into a telescope entry.
--- Each entry tracks its position in the log for chronological sorting.
--- @param index_counter { n: number } Mutable counter shared across entries
--- @return fun(line: string): table|nil
function M.make_entry_maker(index_counter)
	return function(line)
		local sha = line:match("^(%x+)")
		if not sha then
			return nil
		end
		index_counter.n = index_counter.n + 1
		return {
			value = sha,
			display = line,
			ordinal = line,
			index = index_counter.n,
		}
	end
end

--- Build the DiffviewOpen command for the selected commit entries.
--- Pure given its inputs; does not touch vim except for fnameescape, which is
--- injected so this stays unit-testable.
---
--- The "~1" on the older end diffs against that commit's parent, so a single
--- selection shows the changes introduced by that commit.
---
--- One selection  -> "DiffviewOpen <sha>~1"
--- Two selections -> ordered "<older>~1..<newer>" by log index (higher index
---                   = older).
--- @param selections table[]  list of entries with .value (sha) and .index
--- @param current_file_path string|nil  optional file to scope the diff to
--- @param fnameescape fun(path: string): string  escaper (defaults to identity)
--- @return string|nil  the command string, or nil if no selections
function M.build_diff_command(selections, current_file_path, fnameescape)
	if not selections or #selections == 0 then
		return nil
	end
	fnameescape = fnameescape or function(p)
		return p
	end

	local cmd
	if #selections == 1 then
		cmd = "DiffviewOpen " .. selections[1].value .. "~1"
	else
		-- Sort by index: higher index = older (further down the log).
		-- Copy first so we don't mutate the caller's table.
		local sorted = {}
		for i, entry in ipairs(selections) do
			sorted[i] = entry
		end
		table.sort(sorted, function(a, b)
			return a.index > b.index
		end)
		local older = sorted[1].value
		local newer = sorted[2].value
		cmd = "DiffviewOpen " .. older .. "~1.." .. newer
	end

	if current_file_path then
		cmd = cmd .. " -- " .. fnameescape(current_file_path)
	end

	return cmd
end

return M
