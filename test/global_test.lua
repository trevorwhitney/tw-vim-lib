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

H.finish("global.lua")
