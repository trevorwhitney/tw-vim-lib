local helpers = require("tests.agent.spec_helpers")

describe("sidebar lifecycle", function()
	local sidebar

	before_each(function()
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.agent.status"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		helpers.reset_and_mock(false)
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({})
		pcall(sidebar.close)
	end)

	after_each(function()
		pcall(sidebar.close)
	end)

	it("open() creates a window and buffer", function()
		sidebar.open()
		local state = sidebar._state()
		assert.is_true(vim.fn.bufwinid(state.buf) ~= -1)
		assert.is_true(vim.api.nvim_buf_is_valid(state.buf))
	end)

	it("close() is idempotent and preserves the buffer", function()
		sidebar.open()
		local buf = sidebar._state().buf
		sidebar.close()
		sidebar.close() -- second call must not error
		-- Buffer persists (singleton); only the window is gone.
		assert.is_true(vim.api.nvim_buf_is_valid(buf))
		assert.equals(-1, vim.fn.bufwinid(buf))
	end)

	it("toggle() opens when closed, closes when open", function()
		sidebar.toggle()
		assert.is_true(vim.fn.bufwinid(sidebar._state().buf) ~= -1)
		sidebar.toggle()
		assert.equals(-1, vim.fn.bufwinid(sidebar._state().buf))
	end)

	it("setup({ enabled = false }) prevents open from creating a window", function()
		sidebar.close()
		package.loaded["tw.agent.sidebar"] = nil
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({ enabled = false })
		sidebar.open()
		assert.equals(-1, vim.fn.bufwinid(sidebar._state().buf or -1))
	end)

	it("sidebar buffer has buftype=nofile and is unmodifiable by default", function()
		sidebar.open()
		local buf = sidebar._state().buf
		assert.equals("nofile", vim.bo[buf].buftype)
		assert.is_false(vim.bo[buf].modifiable)
	end)

	it("reuses the same buffer across close and reopen", function()
		sidebar.open()
		local buf1 = sidebar._state().buf
		assert.is_true(vim.api.nvim_buf_is_valid(buf1))

		sidebar.close()
		assert.equals(-1, vim.fn.bufwinid(buf1))

		sidebar.open()
		local buf2 = sidebar._state().buf
		assert.equals(buf1, buf2, "reopen must reuse the singleton buffer")
		assert.is_true(vim.fn.bufwinid(buf2) ~= -1)
	end)

	it("is_open() reflects window visibility via bufwinid", function()
		assert.is_false(sidebar.is_open())
		sidebar.open()
		assert.is_true(sidebar.is_open())
		sidebar.close()
		assert.is_false(sidebar.is_open())
	end)
end)

describe("sidebar rendering", function()
	local sidebar
	local agent

	before_each(function()
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.agent.status"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		agent = helpers.reset_and_mock(false)
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({})
		pcall(sidebar.close)
	end)

	after_each(function()
		pcall(sidebar.close)
	end)

	local function setup_alive_instance(mode, idx)
		local buf = vim.api.nvim_create_buf(false, true)
		local job_id = 9000 + idx
		helpers.set_instance(agent, mode, idx, buf, job_id)
		return buf, job_id
	end

	it("refresh() renders empty-state when no instances are alive", function()
		sidebar.open()
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { 0 }
		end
		sidebar.refresh()
		vim.fn.jobwait = orig
		local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
		assert.equals("⌬ Agents", lines[1])
		assert.equals("(no active sessions)", lines[3])
	end)

	it("refresh() renders one row per running instance", function()
		local buf1, job1 = setup_alive_instance("opencode", 0)
		local buf2, job2 = setup_alive_instance("claude", 0)
		-- Terminal text does not affect process liveness.
		vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "all done, which one?" })

		local orig = vim.fn.jobwait
		vim.fn.jobwait = function(jobs)
			local id = jobs[1]
			if id == job1 then
				return { -1 }
			end
			if id == job2 then
				return { -1 }
			end
			return { 0 }
		end

		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig

		-- One row per local terminal.
		local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
		assert.equals(4, #lines)
		assert.is_true(lines[3]:find("oc#0") ~= nil)
		assert.is_true(lines[3]:find("running") ~= nil)
		assert.is_true(lines[4]:find("cl#0") ~= nil)
		assert.is_true(lines[4]:find("running") ~= nil)
	end)

	it("show_dead=false hides dead instances", function()
		setup_alive_instance("opencode", 0)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { 0 }
		end -- all dead
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig
		local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
		for _, l in ipairs(lines) do
			assert.is_nil(l:find("oc#0"))
		end
	end)

	it("show_dead=true keeps dead instances visible", function()
		package.loaded["tw.agent.sidebar"] = nil
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({ show_dead = true })

		setup_alive_instance("opencode", 0)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { 0 }
		end -- exited
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig

		local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
		local found = false
		for _, l in ipairs(lines) do
			if l:find("oc#0") and l:find("dead") then
				found = true
			end
		end
		assert.is_true(found, "oc#0 dead row should be present when show_dead=true")
	end)

	it("docker modes are excluded from sidebar list", function()
		setup_alive_instance("opencode-docker", 0)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig
		local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
		for _, l in ipairs(lines) do
			assert.is_nil(l:find("docker"))
		end
	end)

	it("active session row is recorded in entries", function()
		setup_alive_instance("opencode", 0)
		agent.active_mode = "opencode"
		agent.active_index = 0
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig
		local entries = sidebar._state().entries
		assert.is_true(#entries >= 1)
		assert.is_true(entries[1].is_active)
	end)

	it("active highlight covers only the selected entry", function()
		setup_alive_instance("opencode", 0)
		setup_alive_instance("claude", 0)
		agent.active_mode = "opencode"
		agent.active_index = 0
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig

		local state = sidebar._state()
		local header_row = state.data_start_line - 1
		local marks = vim.api.nvim_buf_get_extmarks(
			state.buf,
			state.ns,
			{ header_row, 0 },
			{ header_row, -1 },
			{ details = true }
		)

		local active_mark
		for _, mark in ipairs(marks) do
			if mark[4] and mark[4].line_hl_group == "TwAgentSidebarActive" then
				active_mark = mark
			end
		end

		assert.is_not_nil(active_mark, "active line highlight extmark should exist")
		-- A line highlight without a range stays on this entry.
		assert.equals(header_row, active_mark[2])
		assert.is_nil(active_mark[4].end_row)
	end)

	it("cursor highlight covers only the selected entry", function()
		setup_alive_instance("opencode", 0)
		setup_alive_instance("claude", 0)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end
		sidebar.open()
		sidebar.refresh()

		local state = sidebar._state()
		local win = vim.fn.bufwinid(state.buf)
		-- Focus the sidebar and place the cursor on the first entry's header.
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_cursor(win, { state.data_start_line, 0 })
		sidebar._apply_cursor_highlight()
		vim.fn.jobwait = orig

		-- The window must not use the built-in single-line cursorline.
		assert.is_false(vim.wo[win].cursorline)

		local header_row = state.data_start_line - 1
		local marks = vim.api.nvim_buf_get_extmarks(
			state.buf,
			state.cursor_ns,
			{ header_row, 0 },
			{ header_row, -1 },
			{ details = true }
		)

		local cursor_mark
		for _, mark in ipairs(marks) do
			if mark[4] and mark[4].line_hl_group == "TwAgentSidebarCursor" then
				cursor_mark = mark
			end
		end

		assert.is_not_nil(cursor_mark, "cursor line highlight extmark should exist")
		assert.equals(header_row, cursor_mark[2])
		assert.is_nil(cursor_mark[4].end_row)
	end)

	it("line_to_entry maps data-row line numbers to entry indices", function()
		setup_alive_instance("opencode", 0)
		setup_alive_instance("claude", 0)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end
		sidebar.open()
		sidebar.refresh()
		vim.fn.jobwait = orig
		-- Each data row maps to one entry.
		local map = sidebar._state().line_to_entry
		assert.equals(1, map[3])
		assert.equals(2, map[4])
		assert.is_nil(map[5])
		assert.is_nil(map[1])
		assert.is_nil(map[2])
	end)
end)

describe("sidebar interaction", function()
	local sidebar
	local agent

	before_each(function()
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.agent.status"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		agent = helpers.reset_and_mock(false)
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({})
		pcall(sidebar.close)
	end)
	after_each(function()
		pcall(sidebar.close)
	end)

	it("open() starts a refresh timer", function()
		sidebar.open()
		assert.is_not_nil(sidebar._state().timer)
	end)

	it("close() stops and clears the timer", function()
		sidebar.open()
		sidebar.close()
		assert.is_nil(sidebar._state().timer)
	end)

	it("<CR> on a data row calls agent.Open with the entry's mode and idx", function()
		local buf = vim.api.nvim_create_buf(false, true)
		helpers.set_instance(agent, "opencode", 0, buf, 9001)
		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end

		local captured = {}
		local orig_open = agent.Open
		agent.Open = function(mode, args, window_type, idx)
			captured = { mode = mode, args = args, window_type = window_type, idx = idx }
		end

		sidebar.open()
		sidebar.refresh()
		vim.api.nvim_win_set_cursor(vim.fn.bufwinid(sidebar._state().buf), { sidebar._state().data_start_line, 0 })
		sidebar._activate_under_cursor()

		agent.Open = orig_open
		vim.fn.jobwait = orig

		assert.equals("opencode", captured.mode)
		assert.equals("vsplit", captured.window_type)
		assert.equals(0, captured.idx)
	end)

	it("<CR> on a non-data row is a no-op", function()
		sidebar.open()
		sidebar.refresh()
		vim.api.nvim_win_set_cursor(vim.fn.bufwinid(sidebar._state().buf), { 1, 0 })
		local called = false
		local orig_open = agent.Open
		agent.Open = function()
			called = true
		end
		sidebar._activate_under_cursor()
		agent.Open = orig_open
		assert.is_false(called)
	end)
end)

describe("sidebar cursor preservation", function()
	local sidebar, agent

	before_each(function()
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.agent.status"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		agent = helpers.reset_and_mock(false)
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({})
		pcall(sidebar.close)
	end)
	after_each(function()
		pcall(sidebar.close)
	end)

	it("preserves cursor on the same (mode, idx) when entries reorder", function()
		local buf1 = vim.api.nvim_create_buf(false, true)
		local buf2 = vim.api.nvim_create_buf(false, true)
		local buf3 = vim.api.nvim_create_buf(false, true)
		helpers.set_instance(agent, "opencode", 0, buf1, 9001)
		helpers.set_instance(agent, "claude", 0, buf2, 9002)
		helpers.set_instance(agent, "codex", 0, buf3, 9003)

		local orig = vim.fn.jobwait
		vim.fn.jobwait = function()
			return { -1 }
		end

		sidebar.open()
		sidebar.refresh()
		local data_start = sidebar._state().data_start_line
		local win = vim.fn.bufwinid(sidebar._state().buf)

		-- Entries are one row apart; park the cursor on codex, the third one.
		vim.api.nvim_win_set_cursor(win, { data_start + 2, 0 })

		-- User is focused on the sidebar window
		vim.api.nvim_set_current_win(win)

		-- Drop opencode so codex becomes the second entry. A preserved cursor
		-- follows codex to data_start + 1; default positioning would instead
		-- fall back to the first row, so this distinguishes the two.
		agent.instances.opencode = {}
		sidebar.refresh()

		assert.equals(data_start + 1, vim.api.nvim_win_get_cursor(win)[1])

		vim.fn.jobwait = orig
	end)
end)

describe("sidebar TermClose autocmd", function()
	local sidebar, agent

	before_each(function()
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.agent.status"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		agent = helpers.reset_and_mock(false)
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({})
		pcall(sidebar.close)
	end)
	after_each(function()
		pcall(sidebar.close)
	end)

	it("registers a TermClose autocmd in the tw_agent_sidebar augroup", function()
		local autocmds = vim.api.nvim_get_autocmds({
			group = "tw_agent_sidebar",
			event = "TermClose",
		})
		assert.is_true(#autocmds >= 1)
		local has_agent_pattern = false
		for _, a in ipairs(autocmds) do
			if a.pattern == "agent://*" then
				has_agent_pattern = true
			end
		end
		assert.is_true(has_agent_pattern)
	end)

	it("does NOT register autocmds when enabled=false", function()
		sidebar.close()
		package.loaded["tw.agent.sidebar"] = nil
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({ enabled = false })
		local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
			group = "tw_agent_sidebar",
			event = "TermClose",
		})
		if ok then
			assert.equals(0, #autocmds)
		end
	end)
end)

describe("sidebar new session (a)", function()
	local sidebar, agent

	before_each(function()
		agent = helpers.reset_and_mock(false)
		package.loaded["tw.agent.sidebar"] = nil
		package.loaded["tw.log"] = {
			info = function() end,
			warn = function() end,
			error = function() end,
			debug = function() end,
		}
		sidebar = require("tw.agent.sidebar")
		sidebar.setup({ enabled = true })
	end)

	after_each(function()
		pcall(sidebar.close)
	end)

	it("returns 0 as the next free index when nothing is used", function()
		assert.equals(0, sidebar.next_free_index("opencode"))
	end)

	it("skips indices held by live instances", function()
		helpers.set_instance(agent, "opencode", 0, vim.api.nvim_create_buf(false, true), 999)
		assert.equals(1, sidebar.next_free_index("opencode"))
	end)

	it("fills the lowest gap between used indices", function()
		helpers.set_instance(agent, "opencode", 0, vim.api.nvim_create_buf(false, true), 999)
		helpers.set_instance(agent, "opencode", 2, vim.api.nvim_create_buf(false, true), 998)
		assert.equals(1, sidebar.next_free_index("opencode"))
	end)

	it("opens a new default-mode session at the next free index", function()
		helpers.set_instance(agent, "opencode", 0, vim.api.nvim_create_buf(false, true), 999)
		local captured
		local orig_open = agent.Open
		agent.Open = function(mode, args, window_type, idx)
			captured = { mode = mode, args = args, window_type = window_type, idx = idx }
		end
		sidebar.new_session()
		agent.Open = orig_open
		assert.equals("opencode", captured.mode)
		assert.equals(1, captured.idx)
		assert.is_nil(captured.args)
	end)

	it("'a' keymap invokes new-session", function()
		local called = false
		local orig = sidebar.new_session
		sidebar.new_session = function()
			called = true
		end
		sidebar.open()
		vim.api.nvim_buf_call(sidebar._state().buf, function()
			vim.cmd("normal a")
		end)
		sidebar.new_session = orig
		assert.is_true(called)
	end)
end)
