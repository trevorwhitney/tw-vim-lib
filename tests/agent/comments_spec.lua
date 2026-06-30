describe("comments add + anchor", function()
	local comments

	before_each(function()
		package.loaded["tw.agent.comments"] = nil
		package.loaded["tw.log"] = { info = function() end, warn = function() end, error = function() end, debug = function() end }
		comments = require("tw.agent.comments")
		comments.clear()
	end)

	after_each(function()
		vim.cmd("silent! %bwipeout!")
	end)

	local function scratch_file(lines)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_current_buf(buf)
		return buf
	end

	it("commits a comment as an extmark and stores the entry", function()
		local buf = scratch_file({ "line1", "line2", "line3", "line4" })
		comments._commit_comment(buf, "src/a.lua", 2, 3, "fix this")
		assert.equals(1, #comments._batch)
		local entry = comments._batch[1]
		assert.equals("src/a.lua", entry.file)
		local s, e = comments._resolve_entry_range(entry)
		assert.equals(2, s)
		assert.equals(3, e)
	end)

	it("range shifts when lines are inserted above the comment", function()
		local buf = scratch_file({ "a", "b", "c", "d" })
		comments._commit_comment(buf, "src/a.lua", 3, 3, "note")
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new1", "new2" })
		local s, e = comments._resolve_entry_range(comments._batch[1])
		assert.equals(5, s)
		assert.equals(5, e)
	end)

	it("renders a virtual-text mark in the namespace", function()
		local buf = scratch_file({ "a", "b" })
		comments._commit_comment(buf, "src/a.lua", 1, 1, "hi")
		local ns = vim.api.nvim_create_namespace("tw_agent_comments")
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
		assert.equals(1, #marks)
		assert.is_truthy(marks[1][4].virt_text)
	end)

	it("list populates the quickfix with one item per comment", function()
		local buf = scratch_file({ "a", "b", "c" })
		comments._commit_comment(buf, "src/a.lua", 1, 1, "first")
		comments._commit_comment(buf, "src/a.lua", 3, 3, "second")
		comments.list()
		local qf = vim.fn.getqflist()
		assert.equals(2, #qf)
		assert.is_truthy(qf[1].text:find("first"))
	end)

	it("remove_under_cursor deletes the comment at the cursor line", function()
		local buf = scratch_file({ "a", "b", "c" })
		comments._commit_comment(buf, "src/a.lua", 2, 2, "kill me")
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		comments.remove_under_cursor()
		assert.equals(0, #comments._batch)
	end)

	it("remove_under_cursor deletes a multi-line comment when cursor is mid-range", function()
		local buf = scratch_file({ "a", "b", "c", "d", "e" })
		comments._commit_comment(buf, "src/a.lua", 2, 4, "spans 2-4")
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		comments.remove_under_cursor()
		assert.equals(0, #comments._batch)
	end)

	it("setup clears orphaned batch state", function()
		local buf = scratch_file({ "a" })
		comments._commit_comment(buf, "src/a.lua", 1, 1, "stale")
		assert.equals(1, #comments._batch)
		comments.setup({})
		assert.equals(0, #comments._batch)
	end)

	it("flush sends the assembled blob through _send_with_count and clears", function()
		package.loaded["tw.agent"] = { _send_with_count = function() end }
		local captured
		package.loaded["tw.agent"]._send_with_count = function(fn_name, count, blob, submit_after)
			captured = { fn_name = fn_name, count = count, blob = blob, submit_after = submit_after }
		end

		local buf = scratch_file({ "a", "b", "c", "d" })
		comments._commit_comment(buf, "src/a.lua", 2, 3, "fix this")
		comments.flush(2)

		assert.equals("SendText", captured.fn_name)
		assert.equals(2, captured.count)
		assert.equals(false, captured.submit_after)
		assert.equals("Review comments:\n\n@src/a.lua:2-3\nfix this", captured.blob)
		assert.equals(0, #comments._batch)

		package.loaded["tw.agent"] = nil
	end)
end)
