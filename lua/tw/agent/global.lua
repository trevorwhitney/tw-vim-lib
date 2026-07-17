local M = {}

local function warn(msg)
	local ok, log = pcall(require, "tw.log")
	if ok and log and log.warn then
		log.warn(msg)
	end
end

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

-- Resolve identity for a worktree root, using the convention first and an
-- optional injected workmux lookup as fallback. opts.workmux_lookup(path) may
-- return { project=, worktree=, handle= } or nil.
local function resolve_identity(root, opts)
	local id = M._derive_identity(root)
	if id and id.project and id.project ~= "" then
		return id
	end
	local lookup = opts and opts.workmux_lookup
	if lookup then
		local ok, fallback = pcall(lookup, root)
		if ok and fallback and fallback.project and fallback.project ~= "" then
			return fallback
		end
	end
	return nil
end

-- Atomic write: tmp file then rename. Best-effort; never raises.
local function write_atomic(dir, filename, payload)
	vim.fn.mkdir(dir, "p")
	local path = dir .. "/" .. filename
	local tmp = path .. ".tmp"
	local ok, err = pcall(function()
		local f = io.open(tmp, "w")
		if not f then
			error("open tmp failed")
		end
		f:write(payload)
		f:close()
		local renamed, rerr = os.rename(tmp, path)
		if not renamed then
			error("rename failed: " .. tostring(rerr))
		end
	end)
	if not ok then
		pcall(os.remove, tmp)
		warn("global.write_atomic: " .. tostring(err))
		return false, err
	end
	return true
end

-- Write (or overwrite) one agent record. Skips entirely if the project cannot
-- be resolved, so a blank-project record is never written.
function M.record(entry, opts)
	opts = opts or {}
	local id = resolve_identity(entry.root, opts)
	if not id then
		return
	end
	local dir = M._agents_dir(opts)
	local filename = M._record_filename(id.project, id.worktree, entry.mode, entry.idx)
	local rec = {
		project = id.project,
		worktree = id.worktree,
		path = entry.root,
		handle = id.handle,
		mode = entry.mode,
		idx = entry.idx,
		status = entry.status or "working",
		description = entry.description,
		session_id = entry.session_id,
		updated_ts = entry.updated_ts or os.time(),
		schema = 1,
	}
	write_atomic(dir, filename, vim.json.encode(rec))
end

-- Update status/updated_ts on an existing mirror record, and the description
-- when a fresh non-empty one is provided. All other fields (session_id, path,
-- handle) are preserved. Skips when no record file exists yet. Used by the
-- periodic heartbeat so descriptions generated after the initial record still
-- reach the mirror, without erasing previously mirrored metadata.
function M.touch(entry, opts)
	opts = opts or {}
	local id = resolve_identity(entry.root, opts)
	if not id then
		return
	end
	local dir = M._agents_dir(opts)
	local filename = M._record_filename(id.project, id.worktree, entry.mode, entry.idx)
	local path = dir .. "/" .. filename
	local f = io.open(path, "r")
	if not f then
		return
	end
	local content = f:read("*a")
	f:close()
	local ok, existing = pcall(vim.json.decode, content)
	if not ok or type(existing) ~= "table" then
		return
	end
	existing.status = entry.status or existing.status
	existing.updated_ts = entry.updated_ts or os.time()
	if entry.description and entry.description ~= "" then
		existing.description = entry.description
	end
	write_atomic(dir, filename, vim.json.encode(existing))
end

-- Mark an exited agent's record restorable, preserving session_id/description.
-- Skips entirely when no prior record file exists (nothing to mark restorable),
-- so a junk record is never created on the exit path.
function M.record_exit(entry, opts)
	opts = opts or {}
	local id = resolve_identity(entry.root, opts)
	if not id then
		return
	end
	local dir = M._agents_dir(opts)
	local filename = M._record_filename(id.project, id.worktree, entry.mode, entry.idx)
	local path = dir .. "/" .. filename
	local f = io.open(path, "r")
	if not f then
		return
	end
	local content = f:read("*a")
	f:close()
	local ok, existing = pcall(vim.json.decode, content)
	if not ok or type(existing) ~= "table" then
		return
	end
	existing.status = "restorable"
	existing.updated_ts = entry.updated_ts or os.time()
	write_atomic(dir, filename, vim.json.encode(existing))
end

-- Remove a record file. No-op if absent.
function M.delete(project, worktree, mode, idx, opts)
	local dir = M._agents_dir(opts or {})
	local filename = M._record_filename(project, worktree, mode, idx)
	pcall(os.remove, dir .. "/" .. filename)
end

return M
