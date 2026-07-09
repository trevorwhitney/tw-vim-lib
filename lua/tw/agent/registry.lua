local M = {}

local log = require("tw.log")

local PRUNE_AGE_SECONDS = 14 * 24 * 60 * 60

local function registry_path(root)
	return root .. "/.workmux/agent-sessions.json"
end

local function key_for(mode, idx)
	return string.format("%s#%d", mode, idx)
end

local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

-- Load the worktree's session registry as a table keyed by "<mode>#<idx>".
-- Entries older than 14 days are dropped. Corrupt or missing files yield {}.
-- The idx field is coerced to a number so lookups against integer-keyed
-- M.instances[mode] succeed.
function M.load(root)
	local content = read_file(registry_path(root))
	if not content or content == "" then
		return {}
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" or type(decoded.sessions) ~= "table" then
		log.warn("registry.load: corrupt or unexpected shape, treating as empty")
		return {}
	end

	local cutoff = os.time() - PRUNE_AGE_SECONDS
	local entries = {}
	for key, entry in pairs(decoded.sessions) do
		local ts = tonumber(type(entry) == "table" and entry.updated_ts or nil) or 0
		if type(entry) == "table" and ts >= cutoff then
			local key_idx = key:match("#(%-?%d+)$")
			entry.idx = tonumber(key_idx) or tonumber(entry.idx) or entry.idx
			entries[key] = entry
		end
	end
	return entries
end

local function write_atomic(root, entries)
	local dir = root .. "/.workmux"
	vim.fn.mkdir(dir, "p")
	local path = registry_path(root)
	local tmp = path .. ".tmp"
	local payload = vim.json.encode({ version = 1, sessions = entries })

	local ok, err = pcall(function()
		local file = io.open(tmp, "w")
		if not file then
			error("failed to open tmp for writing")
		end
		file:write(payload)
		file:close()
		local renamed, rename_err = os.rename(tmp, path)
		if not renamed then
			error("rename failed: " .. tostring(rename_err))
		end
	end)
	if not ok then
		log.warn("registry.write_atomic: " .. tostring(err))
		pcall(os.remove, tmp)
	end
end

-- Insert or update a single session record. fields are merged over the existing
-- record, so a caller that omits a field does not erase it; provided fields
-- overwrite. Callers should include a current updated_ts (load prunes on it).
-- Last-writer-wins across concurrent nvims, acceptable for this best-effort registry.
function M.upsert(root, mode, idx, fields)
	local entries = M.load(root)
	local existing = entries[key_for(mode, idx)] or {}
	local record = vim.tbl_extend("force", existing, fields or {}, {
		mode = mode,
		idx = idx,
	})
	entries[key_for(mode, idx)] = record
	write_atomic(root, entries)
end

-- Remove a single session record. No-op when the key is absent.
function M.delete(root, mode, idx)
	local entries = M.load(root)
	entries[key_for(mode, idx)] = nil
	write_atomic(root, entries)
end

M._key_for = key_for

return M
