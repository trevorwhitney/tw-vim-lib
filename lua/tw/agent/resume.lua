local M = {}

local log = require("tw.log")

local function default_list_sessions()
	local pipe = io.popen("opencode session list --format json 2>/dev/null")
	if not pipe then
		return nil
	end
	local out = pipe:read("*a")
	pipe:close()
	return out
end

local function matching_sessions(json_text, cwd)
	if not json_text or json_text == "" then
		return nil
	end
	local ok, rows = pcall(vim.json.decode, json_text)
	if not ok or type(rows) ~= "table" then
		log.warn("resume: failed to decode session list")
		return nil
	end
	local matches = {}
	for _, row in ipairs(rows) do
		if type(row) == "table" and row.directory == cwd and row.id then
			row._updated = tonumber(row.updated) or 0
			table.insert(matches, row)
		end
	end
	table.sort(matches, function(a, b)
		return a._updated > b._updated
	end)
	return matches
end

-- Pick the opencode session a freshly-launched panel should own: the newest
-- session in cwd, created at/after launch_ts (ms), whose id is not in
-- claimed_ids. Returns the id or nil. opts.list_sessions overrides the default
-- `opencode session list` command (used by tests). Never throws.
function M.capture_session_id(cwd, launch_ts, claimed_ids, opts)
	opts = opts or {}
	claimed_ids = claimed_ids or {}
	local list_sessions = opts.list_sessions or default_list_sessions
	local ok, json_text = pcall(list_sessions)
	if not ok or not json_text or json_text == "" then
		return nil
	end
	local ok_decode, rows = pcall(vim.json.decode, json_text)
	if not ok_decode or type(rows) ~= "table" then
		return nil
	end
	local candidates = {}
	for _, row in ipairs(rows) do
		local created = tonumber(type(row) == "table" and row.created or nil)
		if
			type(row) == "table"
			and row.directory == cwd
			and type(row.id) == "string"
			and not claimed_ids[row.id]
			and created
			and created >= launch_ts
		then
			row._created = created
			table.insert(candidates, row)
		end
	end
	table.sort(candidates, function(a, b)
		if a._created ~= b._created then
			return a._created > b._created
		end
		return a.id > b.id
	end)
	if candidates[1] then
		return candidates[1].id
	end
	return nil
end

-- Build the CLI args that relaunch a prior session.
--   opencode -> { "--session", <id> } (most-recent session in cwd), else { "--continue" }
--   claude   -> { "--continue" }
--   codex/pi -> {} (fresh launch; no resume support in v1)
-- opts.list_sessions: function returning `opencode session list --format json` output.
function M.args_for(mode, _idx, cwd, opts)
	opts = opts or {}
	if mode == "claude" then
		return { "--continue" }
	end
	if mode ~= "opencode" then
		return {}
	end

	local list_sessions = opts.list_sessions or default_list_sessions
	local ok, json_text = pcall(list_sessions)
	if not ok then
		log.warn("resume: session list command failed")
		return { "--continue" }
	end
	local matches = matching_sessions(json_text, cwd)
	if matches and matches[1] then
		return { "--session", matches[1].id }
	end
	return { "--continue" }
end

return M
