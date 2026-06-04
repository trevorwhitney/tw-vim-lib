-- Standalone tests for tw.agent.claude.command()
-- Run: lua test/claude_command_test.lua (or via make test-lua)
--
-- claude.lua computes sandbox availability at require() time from
-- vim.fn.executable, and resolves the agent binary via io.popen("command -v").
-- We stub both, then reload the module per-scenario to exercise the
-- sandbox-available and no-sandbox code paths and the per-agent flag table.

local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

-- ---------------------------------------------------------------------------
-- Stubs
-- ---------------------------------------------------------------------------
local SANDBOX_PATH = "/home/user/.config/sandbox-exec/run-sandboxed.sh"

-- Records vim.notify / nvim_err_writeln calls for assertions.
local notifications = {}
local err_writes = {}

-- Builds a vim stub. sandbox_executable controls whether the sandbox wrapper
-- is considered installed (drives vim.fn.executable for the wrapper path).
local function make_vim(sandbox_executable)
	return {
		fn = {
			expand = function(p)
				-- The module only expands the sandbox wrapper path.
				return p:gsub("^~", "/home/user")
			end,
			executable = function(_p)
				return sandbox_executable and 1 or 0
			end,
			shellescape = function(s)
				return "'" .. s .. "'"
			end,
		},
		api = {
			nvim_err_writeln = function(msg)
				table.insert(err_writes, msg)
			end,
		},
		notify = function(msg, _level)
			table.insert(notifications, msg)
		end,
		log = { levels = { WARN = 3, INFO = 2 } },
		tbl_isempty = function(t)
			return next(t) == nil
		end,
		tbl_keys = function(t)
			local keys = {}
			for k in pairs(t) do
				table.insert(keys, k)
			end
			return keys
		end,
	}
end

-- io.popen stub: makes `command -v <name>` resolve to /usr/local/bin/<name>,
-- or to nothing for the sentinel name "missing".
local real_popen = io.popen
local function stub_popen()
	io.popen = function(cmd)
		local name = cmd:match("command %-v (%S+)")
		local path = (name and name ~= "missing") and ("/usr/local/bin/" .. name) or ""
		return {
			read = function()
				return path .. "\n"
			end,
			close = function() end,
		}
	end
end

-- Loads a fresh claude module under a vim stub with given sandbox availability.
local function load_claude(sandbox_executable)
	notifications = {}
	err_writes = {}
	vim = make_vim(sandbox_executable)
	stub_popen()
	package.loaded["tw.agent.claude"] = nil
	return require("tw.agent.claude")
end

print("agent.claude.command tests:")
print()

-- ---------------------------------------------------------------------------
-- No-sandbox path
-- ---------------------------------------------------------------------------
test("no sandbox: claude gets binary + skip-permissions flag + args", function()
	local claude = load_claude(false)
	local cmd = claude.command({ "-p", "hello" }, "claude")
	eq(
		"/usr/local/bin/claude --dangerously-skip-permissions -p hello",
		cmd,
		"command"
	)
end)

test("no sandbox: warns once about missing sandbox wrapper", function()
	local claude = load_claude(false)
	claude.command({}, "claude")
	claude.command({}, "claude")
	eq(1, #notifications, "notify call count (warn-once)")
	if not notifications[1]:match("Sandbox wrapper not found") then
		error("unexpected notification: " .. tostring(notifications[1]))
	end
end)

test("codex gets --full-auto flag", function()
	local claude = load_claude(false)
	eq("/usr/local/bin/codex --full-auto", claude.command({}, "codex"), "command")
end)

test("opencode gets no extra flags", function()
	local claude = load_claude(false)
	eq("/usr/local/bin/opencode", claude.command({}, "opencode"), "command")
end)

test("defaults command_name to claude when nil", function()
	local claude = load_claude(false)
	eq(
		"/usr/local/bin/claude --dangerously-skip-permissions",
		claude.command({}, nil),
		"command"
	)
end)

-- ---------------------------------------------------------------------------
-- args coercion
-- ---------------------------------------------------------------------------
test("string args is wrapped into a single-element list", function()
	local claude = load_claude(false)
	eq(
		"/usr/local/bin/claude --dangerously-skip-permissions hello",
		claude.command("hello", "claude"),
		"command"
	)
end)

test("non-table non-string args is treated as empty", function()
	local claude = load_claude(false)
	eq(
		"/usr/local/bin/claude --dangerously-skip-permissions",
		claude.command(42, "claude"),
		"command"
	)
end)

-- ---------------------------------------------------------------------------
-- Missing binary
-- ---------------------------------------------------------------------------
test("missing executable returns nil and writes an error", function()
	local claude = load_claude(false)
	local cmd = claude.command({}, "missing")
	eq(nil, cmd, "command")
	eq(1, #err_writes, "err write count")
	if not err_writes[1]:match("executable not found") then
		error("unexpected err: " .. tostring(err_writes[1]))
	end
end)

-- ---------------------------------------------------------------------------
-- Sandbox path
-- ---------------------------------------------------------------------------
test("sandbox: wrapper prefixes the command", function()
	local claude = load_claude(true)
	local cmd = claude.command({ "-p" }, "claude")
	eq(
		SANDBOX_PATH .. " /usr/local/bin/claude --dangerously-skip-permissions -p",
		cmd,
		"command"
	)
end)

test("sandbox: context dirs add sorted --add-dirs (shellescaped)", function()
	local claude = load_claude(true)
	local cmd = claude.command({}, "claude", {
		["/z/last"] = true,
		["/a/first"] = true,
		["/m/middle"] = true,
	})
	eq(
		SANDBOX_PATH
			.. " '--add-dirs=/a/first:/m/middle:/z/last'"
			.. " /usr/local/bin/claude --dangerously-skip-permissions",
		cmd,
		"command"
	)
end)

test("sandbox: empty context_directories omits --add-dirs", function()
	local claude = load_claude(true)
	local cmd = claude.command({}, "claude", {})
	eq(
		SANDBOX_PATH .. " /usr/local/bin/claude --dangerously-skip-permissions",
		cmd,
		"command"
	)
end)

test("sandbox: nil context_directories omits --add-dirs", function()
	local claude = load_claude(true)
	local cmd = claude.command({}, "opencode", nil)
	eq(SANDBOX_PATH .. " /usr/local/bin/opencode", cmd, "command")
end)

-- restore io.popen
io.popen = real_popen

H.finish()
