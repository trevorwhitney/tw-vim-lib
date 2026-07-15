local M = {}

-- Resolve the mirror agents directory. opts.xdg_state / opts.home override the
-- environment (used by tests); production reads XDG_STATE_HOME then HOME.
function M._agents_dir(opts)
	opts = opts or {}
	local xdg = opts.xdg_state or os.getenv("XDG_STATE_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/agentmux/agents"
	end
	local home = opts.home or os.getenv("HOME") or ""
	return home .. "/.local/state/agentmux/agents"
end

-- Percent-encode one path component so it cannot contain the "__" delimiter or
-- otherwise collide. vim.uri_encode leaves "_" intact, so escape it explicitly:
-- with no literal "_" inside a component, "__" is an unambiguous separator.
local function enc(component)
	return (vim.uri_encode(tostring(component)):gsub("_", "%%5F"))
end

-- Build the record filename. mode is a fixed identifier and idx is 0-9, so
-- "<mode>#<idx>" is left unencoded for readability.
function M._record_filename(project, worktree, mode, idx)
	return string.format("%s__%s__%s#%d.json", enc(project), enc(worktree), mode, idx)
end

-- Derive { project, worktree, handle } from a worktree root path using the
-- ~/workspace/<project>/<worktree> convention. Requires a "workspace" segment
-- with at least a project and worktree after it; returns nil otherwise so the
-- caller can fall back to workmux or skip. Pure string work.
function M._derive_identity(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local segments = {}
	for seg in path:gmatch("[^/]+") do
		table.insert(segments, seg)
	end
	local ws_index = nil
	for i, seg in ipairs(segments) do
		if seg == "workspace" then
			ws_index = i
		end
	end
	if not ws_index or #segments < ws_index + 2 then
		return nil
	end
	local worktree = segments[#segments]
	local project = segments[#segments - 1]
	return {
		project = project,
		worktree = worktree,
		handle = worktree,
	}
end

return M
