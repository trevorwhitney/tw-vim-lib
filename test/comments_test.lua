-- Standalone tests for tw.agent.comments pure logic.
-- Run: lua test/comments_test.lua (or via make test-lua)
-- Stubs vim + plenary.path so this runs outside Neovim.

package.preload["plenary.path"] = function()
	local Path = {}
	Path.__index = Path
	function Path:make_relative(root)
		if root and self.filename:sub(1, #root) == root then
			return self.filename:sub(#root + 2)
		end
		return self.filename
	end
	function Path:new(path_str)
		return setmetatable({ filename = path_str }, Path)
	end
	return Path
end

package.preload["tw.log"] = function()
	return { info = function() end, warn = function() end, error = function() end, debug = function() end }
end

vim = vim
	or {
		api = {
			nvim_create_namespace = function()
				return 1
			end,
		},
		fn = {
			filereadable = function()
				return 1
			end,
			expand = function()
				return ""
			end,
		},
		bo = setmetatable({}, { __index = function()
			return { buftype = "" }
		end }),
		notify = function() end,
		log = { levels = { WARN = 3, INFO = 2 } },
	}

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

print("comments tests:")
print()

-- Install a fake extmark seam shared by tests that need it.
local function fake_ops()
	local store = {}
	local next_id = 0
	return {
		store = store,
		set = function(_, start_row, end_row, _)
			next_id = next_id + 1
			store[next_id] = { start_line = start_row + 1, end_line = (end_row or start_row) + 1 }
			return next_id
		end,
		get = function(_, id)
			return store[id]
		end,
		del = function(_, id)
			store[id] = nil
		end,
		clear = function() end,
		buf_valid = function()
			return true
		end,
	}
end

test("clear empties the batch", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	comments._extmark_ops = fake_ops()
	comments._batch = { { bufnr = 1, extmark_id = 1, file = "a.lua", body = "x", start_line = 1, end_line = 1 } }
	comments._marked_bufs = { [1] = true }
	comments.clear()
	eq(0, #comments._batch, "batch length")
end)

test("is_commentable_buffer accepts a plain readable file path", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq(true, comments._is_commentable_buffer("/repo/src/a.lua", 1), "plain path")
end)

test("is_commentable_buffer rejects diffview commit (base) buffers", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq(false, comments._is_commentable_buffer("diffview:///repo/.git/abc123/src/a.lua", 1), "base side")
end)

test("is_commentable_buffer rejects diffview stage :0: (index) buffers", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq(false, comments._is_commentable_buffer("diffview:///repo/.git/:0:/src/a.lua", 1), "index side")
end)

test("is_commentable_buffer rejects empty buffer name", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq(false, comments._is_commentable_buffer("", 1), "empty name")
end)

test("is_commentable_buffer rejects non-file buftype (e.g. terminal)", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	local saved_bo = vim.bo
	vim.bo = setmetatable({}, { __index = function()
		return { buftype = "terminal" }
	end })
	local ok = comments._is_commentable_buffer("/repo/src/a.lua", 1)
	vim.bo = saved_bo
	eq(false, ok, "terminal buffer rejected")
end)

test("render_range collapses single line to :N", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq("a.lua:42", comments._render_range("a.lua", 42, 42), "single line")
end)

test("render_range keeps :start-end for a range", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	eq("a.lua:42-50", comments._render_range("a.lua", 42, 50), "range")
end)

test("format_block emits @path:range then body", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	local block = comments._format_block({ file = "src/a.lua", start_line = 10, end_line = 12, body = "fix this" })
	eq("@src/a.lua:10-12\nfix this", block, "block")
end)

test("build_blob joins blocks with header and blank-line separators", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	local blob = comments._build_blob({
		{ file = "a.lua", start_line = 1, end_line = 1, body = "one" },
		{ file = "b.lua", start_line = 5, end_line = 7, body = "two" },
	})
	eq("Review comments:\n\n@a.lua:1\none\n\n@b.lua:5-7\ntwo", blob, "blob")
end)

test("resolve_entry_range uses the live extmark range when available", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	local ops = fake_ops()
	comments._extmark_ops = ops
	-- Seed a live extmark spanning rows 4..6 (0-based) -> lines 5..7.
	local id = ops.set(1, 4, 6, {})
	local entry = { bufnr = 1, extmark_id = id, file = "a.lua", body = "x", start_line = 99, end_line = 99 }
	local s, e = comments._resolve_entry_range(entry)
	eq(5, s, "start from extmark")
	eq(7, e, "end from extmark")
end)

test("resolve_entry_range falls back to stored range when extmark is gone", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	comments._extmark_ops = fake_ops() -- empty store -> get returns nil
	local entry = { bufnr = 1, extmark_id = 123, file = "a.lua", body = "x", start_line = 8, end_line = 9 }
	local s, e = comments._resolve_entry_range(entry)
	eq(8, s, "fallback start")
	eq(9, e, "fallback end")
end)

test("flush sends the assembled blob via the send seam and clears", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	local ops = fake_ops()
	comments._extmark_ops = ops
	local id1 = ops.set(1, 9, 11, {}) -- lines 10..12
	local id2 = ops.set(1, 4, 4, {}) -- line 5
	comments._batch = {
		{ bufnr = 1, extmark_id = id1, file = "a.lua", body = "one", start_line = 10, end_line = 12 },
		{ bufnr = 1, extmark_id = id2, file = "b.lua", body = "two", start_line = 5, end_line = 5 },
	}
	comments._marked_bufs = { [1] = true }
	local sent
	comments._send = function(count, blob)
		sent = { count = count, blob = blob }
	end
	comments.flush(3)
	eq(3, sent.count, "count forwarded")
	eq("Review comments:\n\n@a.lua:10-12\none\n\n@b.lua:5\ntwo", sent.blob, "blob")
	eq(0, #comments._batch, "batch cleared after flush")
end)

test("flush on empty batch notifies and does not send", function()
	local comments = dofile("lua/tw/agent/comments.lua")
	comments._extmark_ops = fake_ops()
	comments._batch = {}
	local sent = false
	comments._send = function()
		sent = true
	end
	local notified
	local saved_notify = vim.notify
	vim.notify = function(msg)
		notified = msg
	end
	comments.flush(0)
	vim.notify = saved_notify
	eq(false, sent, "nothing sent")
	eq(true, notified ~= nil, "notified about empty batch")
end)

H.finish()
