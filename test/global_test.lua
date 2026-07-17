local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Make env lookups deterministic regardless of the ambient shell.
local fake_env = {}
-- luacheck: ignore 122 (setting read-only global field os.getenv)
os.getenv = function(name)
	if fake_env[name] ~= nil then
		return fake_env[name]
	end
	return nil
end

_G.vim = {
	fn = {
		mkdir = function()
			return 1
		end,
	},
	uri_encode = function(str)
		-- percent-encode everything but unreserved chars (RFC 3986)
		return (str:gsub("[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end,
}

-- In-memory filesystem the io.open/os.rename overrides operate on.
local fake_fs = {}
local real_open = io.open
-- luacheck: ignore 122 (setting read-only global field io.open)
io.open = function(path, mode)
	if mode == "w" then
		return {
			write = function(_, data)
				fake_fs[path] = data
			end,
			close = function() end,
		}
	elseif mode == "r" then
		local data = fake_fs[path]
		if not data then
			return nil
		end
		return {
			read = function()
				return data
			end,
			close = function() end,
		}
	end
	return real_open(path, mode)
end
-- luacheck: ignore 122 (setting read-only global field os.rename)
os.rename = function(from, to)
	fake_fs[to] = fake_fs[from]
	fake_fs[from] = nil
	return true
end
-- luacheck: ignore 122 (setting read-only global field os.remove)
os.remove = function(path)
	fake_fs[path] = nil
	return true
end

-- Deep-copy JSON stub: encode/decode return independent copies so the "file"
-- is a distinct object from any in-memory table. This makes record_exit tests
-- prove an actual re-write (not in-place mutation of a shared table).
local function deep_copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in pairs(v) do
		out[k] = deep_copy(val)
	end
	return out
end
_G.vim.json = {
	encode = function(t)
		return deep_copy(t)
	end,
	decode = function(t)
		return deep_copy(t)
	end,
}

local global = dofile("lua/tw/agent/global.lua")

test("agents_dir honors XDG_STATE_HOME", function()
	local dir = global._agents_dir({ xdg_state = "/tmp/xdg" })
	eq("/tmp/xdg/agentmux/agents", dir, "xdg path")
end)

test("agents_dir falls back to HOME/.local/state", function()
	local dir = global._agents_dir({ xdg_state = nil, home = "/home/tw" })
	eq("/home/tw/.local/state/agentmux/agents", dir, "home fallback")
end)

test("filename percent-encodes components and joins with __", function()
	local name = global._record_filename("loki", "logmerge-build-index", "opencode", 0)
	eq("loki__logmerge-build-index__opencode#0.json", name, "simple")
end)

test("filename encodes slashes from a remote-derived project", function()
	local name = global._record_filename("github.com/org/repo", "wt", "opencode", 1)
	eq("github.com%2Forg%2Frepo__wt__opencode#1.json", name, "encoded slash")
end)

test("filename escapes underscores so __ delimiter is unambiguous", function()
	local a = global._record_filename("a_", "_b", "opencode", 0)
	local b = global._record_filename("a", "__b", "opencode", 0)
	eq(false, a == b, "distinct pairs must not collide")
	eq("a%5F__%5Fb__opencode#0.json", a, "underscore encoding")
end)

test("derive splits ~/workspace/<project>/<worktree>", function()
	local d = global._derive_identity("/Users/tw/workspace/loki/logmerge-build-index")
	eq("loki", d.project, "project")
	eq("logmerge-build-index", d.worktree, "worktree")
	eq("logmerge-build-index", d.handle, "handle")
end)

test("derive handles a main checkout (project == worktree)", function()
	local d = global._derive_identity("/Users/tw/workspace/loki/loki")
	eq("loki", d.project, "project")
	eq("loki", d.worktree, "worktree")
end)

test("derive returns nil for a path with no workspace segment", function()
	eq(nil, global._derive_identity("/tmp/scratch"), "non-workspace 2-seg")
	eq(nil, global._derive_identity("/"), "root path")
	eq(nil, global._derive_identity("/Users/tw/workspace/loki"), "workspace but no worktree")
end)

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

test("record writes an atomic file with derived identity", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/logmerge-build-index",
		mode = "opencode",
		idx = 0,
		status = "working",
		description = "add compaction metrics",
		session_id = "ses_1",
		updated_ts = 111,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__logmerge-build-index__opencode#0.json"
	local rec = fake_fs[path] -- identity json: the table itself
	eq(true, rec ~= nil, "file exists")
	eq("loki", rec.project, "project")
	eq("working", rec.status, "status")
	eq("ses_1", rec.session_id, "session_id")
	eq(1, rec.schema, "schema")
end)

test("record skips write when identity and fallback cannot resolve project", function()
	fake_fs = {}
	global.record({
		root = "/",
		mode = "opencode",
		idx = 0,
		status = "working",
		updated_ts = 1,
	}, {
		xdg_state = "/tmp/xdg",
		workmux_lookup = function()
			return nil
		end,
	})
	eq(0, count(fake_fs), "no files written")
end)

test("record_exit sets status restorable, preserves session_id", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		session_id = "ses_9",
		updated_ts = 5,
	}, { xdg_state = "/tmp/xdg" })
	global.record_exit({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		updated_ts = 6,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__wt__opencode#0.json"
	eq("restorable", fake_fs[path].status, "status")
	eq("ses_9", fake_fs[path].session_id, "session_id preserved")
end)

test("record_exit writes nothing when no prior record file exists", function()
	fake_fs = {}
	global.record_exit({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		updated_ts = 6,
	}, { xdg_state = "/tmp/xdg" })
	eq(0, count(fake_fs), "no junk record created")
end)

test("record_exit freezes updated_ts at the passed exit time", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		updated_ts = 100,
	}, { xdg_state = "/tmp/xdg" })
	global.record_exit({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		updated_ts = 142,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__wt__opencode#0.json"
	eq(142, fake_fs[path].updated_ts, "updated_ts frozen at exit time")
end)

test("delete removes the record file", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "[REDACTED]",
		idx = 0,
		status = "working",
		updated_ts = 5,
	}, { xdg_state = "/tmp/xdg" })
	global.delete("loki", "wt", "[REDACTED]", 0, { xdg_state = "/tmp/xdg" })
	local path = "[REDACTED]#0.json"
	eq(nil, fake_fs[path], "file gone")
end)

test("touch updates status/updated_ts but preserves session_id and description", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		session_id = "ses_keep",
		description = "do the thing",
		updated_ts = 100,
	}, { xdg_state = "/tmp/xdg" })
	global.touch({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		updated_ts = 205,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__wt__opencode#0.json"
	eq("ses_keep", fake_fs[path].session_id, "session_id preserved")
	eq("do the thing", fake_fs[path].description, "description preserved")
	eq(205, fake_fs[path].updated_ts, "updated_ts advanced")
end)

test("touch updates description when a fresh one is provided", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		session_id = "ses_keep",
		description = "old summary",
		updated_ts = 100,
	}, { xdg_state = "/tmp/xdg" })
	global.touch({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		description = "new summary",
		updated_ts = 205,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__wt__opencode#0.json"
	eq("new summary", fake_fs[path].description, "description updated")
	eq("ses_keep", fake_fs[path].session_id, "session_id preserved")
end)

test("touch preserves existing description when none is provided", function()
	fake_fs = {}
	global.record({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		description = "keep me",
		updated_ts = 100,
	}, { xdg_state = "/tmp/xdg" })
	global.touch({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		updated_ts = 205,
	}, { xdg_state = "/tmp/xdg" })
	local path = "/tmp/xdg/agentmux/agents/loki__wt__opencode#0.json"
	eq("keep me", fake_fs[path].description, "description preserved when not provided")
end)

test("touch writes nothing when no prior record exists", function()
	fake_fs = {}
	global.touch({
		root = "/Users/tw/workspace/loki/wt",
		mode = "opencode",
		idx = 0,
		status = "working",
		updated_ts = 5,
	}, { xdg_state = "/tmp/xdg" })
	local n = 0
	for _ in pairs(fake_fs) do
		n = n + 1
	end
	eq(0, n, "no record created")
end)

H.finish("global.lua")
