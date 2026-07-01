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
