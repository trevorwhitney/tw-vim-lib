local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.vim = { json = {
	encode = function()
		return "{}"
	end,
} }

-- Stub the registry require so publish loads without Neovim.
package.loaded["tw.agent.registry"] = {
	upsert = function() end,
}

local publish = dofile("lua/tw/agent/publish.lua")

test("record mirrors into global with normalized description", function()
	local calls = {}
	publish._set_global({
		record = function(entry)
			table.insert(calls, entry)
		end,
		record_exit = function() end,
	})
	publish.record({
		root = "/w/loki/wt",
		mode = "opencode",
		idx = 0,
		cwd = "/w/loki/wt",
		status = "working",
		description = "loading",
		session_id = "s1",
	})
	eq(1, #calls, "mirror called once")
	eq("/w/loki/wt", calls[1].root, "root passed")
	eq(nil, calls[1].description, "loading normalized to nil")
	eq("s1", calls[1].session_id, "session id passed")
end)

test("record_exit mirrors into global", function()
	local exits = {}
	publish._set_global({
		record = function() end,
		record_exit = function(entry)
			table.insert(exits, entry)
		end,
	})
	publish.record_exit({ root = "/w/loki/wt", mode = "opencode", idx = 0, cwd = "/w/loki/wt" })
	eq(1, #exits, "mirror exit called once")
	eq("/w/loki/wt", exits[1].root, "root passed")
end)

test("a throwing global mirror does not break record or record_exit", function()
	publish._set_global({
		record = function()
			error("mirror boom")
		end,
		record_exit = function()
			error("mirror boom")
		end,
	})
	-- Neither call should raise; the authoritative registry.upsert already ran.
	local ok_record = pcall(publish.record, {
		root = "/w/loki/wt",
		mode = "opencode",
		idx = 0,
		cwd = "/w/loki/wt",
		status = "working",
	})
	local ok_exit = pcall(publish.record_exit, {
		root = "/w/loki/wt",
		mode = "opencode",
		idx = 0,
		cwd = "/w/loki/wt",
	})
	eq(true, ok_record, "record must not raise when mirror throws")
	eq(true, ok_exit, "[REDACTED] must not raise when mirror throws")
end)

test("heartbeat writes mirror at most once per interval", function()
	local writes = {}
	publish._set_global({
		record = function(entry)
			table.insert(writes, entry)
		end,
		record_exit = function() end,
		touch = function(entry)
			table.insert(writes, entry)
		end,
	})
	local t = 0
	publish._set_clock(function()
		return t
	end)
	publish._reset_heartbeat()

	local inst = { root = "/w/loki/wt", mode = "opencode", idx = 0, status = "working" }

	t = 1000
	publish.heartbeat(inst) -- first write always allowed
	eq(1, #writes, "first write succeeded")
	t = 4999
	publish.heartbeat(inst) -- 3999ms later: still throttled
	eq(1, #writes, "suppressed before interval")
	t = 5000
	publish.heartbeat(inst) -- exactly 4000ms later: allowed
	eq(2, #writes, "allowed at interval boundary")
end)

test("a mirror record() resets the heartbeat throttle for that key", function()
	local writes = {}
	publish._set_global({
		record = function(entry)
			table.insert(writes, entry)
		end,
		record_exit = function() end,
		touch = function(entry)
			table.insert(writes, entry)
		end,
	})
	local t = 10000
	publish._set_clock(function()
		return t
	end)
	publish._reset_heartbeat()

	publish.record({ root = "/w/loki/wt", mode = "opencode", idx = 0, status = "working" })
	local after_record = #writes
	t = 11000
	publish.heartbeat({ root = "/w/loki/wt", mode = "opencode", idx = 0, status = "working" })
	eq(after_record, #writes, "heartbeat suppressed within interval of a record()")
end)

H.finish("publish.lua")
