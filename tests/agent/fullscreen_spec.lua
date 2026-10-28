local helpers = require("tests.agent.spec_helpers")

describe("fullscreen edgy opt-out", function()
	local agent, claude_mod

	before_each(function()
		agent, claude_mod = helpers.reset_and_mock(true)
		claude_mod.command = function()
			return "sleep 30"
		end
		pcall(vim.cmd, "enew")
	end)

	after_each(function()
		agent.agent_fullscreen = false
		for _, _, _, job_id in agent._iter_all_instances() do
			if job_id then
				pcall(vim.fn.jobstop, job_id)
			end
		end
		pcall(vim.cmd, "only")
	end)

	it("sets edgy_disable on the agent buffer when fullscreen", function()
		agent.agent_fullscreen = true
		agent.Open("opencode", nil, "current", 0)
		local inst = agent._get_instance("opencode", 0)
		assert.is_not_nil(inst)
		assert.is_true(vim.b[inst.buf].edgy_disable == true)
	end)

	it("does not set edgy_disable for a normal (non-fullscreen) open", function()
		agent.agent_fullscreen = false
		agent.Open("opencode", nil, "vsplit", 0)
		local inst = agent._get_instance("opencode", 0)
		assert.is_not_nil(inst)
		assert.is_not_true(vim.b[inst.buf].edgy_disable)
	end)

	it("clears edgy_disable when the fullscreen revert autocmd fires", function()
		require("tw.agent.commands").setup_autocmds(agent)
		agent.agent_fullscreen = true
		agent.Open("opencode", nil, "current", 0)
		local inst = agent._get_instance("opencode", 0)
		assert.is_true(vim.b[inst.buf].edgy_disable == true)

		vim.cmd("enew")
		vim.bo.buftype = ""
		vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() })

		assert.is_false(vim.b[inst.buf].edgy_disable)
	end)
end)

describe("fullscreen agent args", function()
	local agent, claude_mod, captured, captured_auto_permissions

	before_each(function()
		agent, claude_mod = helpers.reset_and_mock(true)
		captured = nil
		captured_auto_permissions = nil
		claude_mod.command = function(args, _mode, _context_directories, auto_permissions)
			captured = args
			captured_auto_permissions = auto_permissions
			return "sleep 30"
		end
		pcall(vim.cmd, "enew")
	end)

	after_each(function()
		agent.agent_fullscreen = false
		for _, _, _, job_id in agent._iter_all_instances() do
			if job_id then
				pcall(vim.fn.jobstop, job_id)
			end
		end
		pcall(vim.cmd, "only")
	end)

	-- OpenFullscreen defers the termopen to VimEnter when it runs during startup,
	-- which is where a headless `-c` command lands. Drive that path to completion
	-- so the assertions see the command that was actually built.
	local function wait_for_command()
		if vim.v.vim_did_enter == 0 then
			vim.api.nvim_exec_autocmds("VimEnter", {})
		end
		vim.wait(2000, function()
			return captured ~= nil
		end)
	end

	it("forwards extra args to the agent command line", function()
		agent.OpenFullscreen("opencode", "--prompt 'this is a test'")
		wait_for_command()

		assert.is_not_nil(captured)
		assert.equals("--prompt 'this is a test'", captured[#captured])
	end)

	for _, case in ipairs({
		{ "claude", "--resume session-123" },
		{ "codex", "resume session-123" },
		{ "opencode", "--session session-123" },
		{ "claude", "--continue" },
		{ "codex", "resume --last" },
		{ "opencode", "--continue" },
	}) do
		it("forwards explicit continuation: " .. case[1] .. " " .. case[2], function()
			require("tw.agent.commands").setup_user_commands(agent)
			vim.cmd("AgentFullscreen " .. case[1] .. " " .. case[2])
			wait_for_command()
			assert.equals(case[2], captured[#captured])
			assert.is_false(captured_auto_permissions)
		end)
	end

	it("passes no extra args when none are given", function()
		agent.OpenFullscreen("opencode")
		wait_for_command()

		assert.is_not_nil(captured)
		-- Only the project root that start_new_agent_job prepends for opencode.
		assert.equals(1, #captured)
	end)

	it("does not inject permission flags for fullscreen command launches", function()
		agent.OpenFullscreen("claude", "--model opus")
		wait_for_command()

		assert.is_false(captured_auto_permissions)
	end)

	it("emits TwAgentStarted after launching the fullscreen agent", function()
		local fired = false
		vim.api.nvim_create_autocmd("User", {
			pattern = "TwAgentStarted",
			once = true,
			callback = function()
				fired = true
			end,
		})

		agent.OpenFullscreen("opencode")
		wait_for_command()
		vim.wait(2000, function()
			return fired
		end)

		assert.is_true(fired)
	end)

	it("injects permission flags for in-editor launches", function()
		agent.Toggle("claude")
		wait_for_command()

		assert.is_true(captured_auto_permissions)
	end)

	it(":AgentFullscreen forwards everything after the mode verbatim", function()
		require("tw.agent.commands").setup_user_commands(agent)

		vim.cmd("AgentFullscreen opencode --prompt 'this is a test'")
		wait_for_command()

		assert.is_not_nil(captured)
		assert.equals("--prompt 'this is a test'", captured[#captured])
	end)

	it(":AgentFullscreen still accepts a bare mode", function()
		require("tw.agent.commands").setup_user_commands(agent)

		vim.cmd("AgentFullscreen opencode")
		wait_for_command()

		assert.is_not_nil(captured)
		assert.equals(1, #captured)
	end)
end)

describe("fullscreen focus keymaps", function()
	local agent, claude_mod

	before_each(function()
		agent, claude_mod = helpers.reset_and_mock(true)
		claude_mod.command = function()
			return "sleep 30"
		end
		pcall(vim.cmd, "only")
		pcall(vim.cmd, "enew")
	end)

	after_each(function()
		agent.agent_fullscreen = false
		for _, _, _, job_id in agent._iter_all_instances() do
			if job_id then
				pcall(vim.fn.jobstop, job_id)
			end
		end
		pcall(vim.cmd, "only")
	end)

	it("starts the requested instance alone without hijacking the file buffer", function()
		local file_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, { "file contents" })
		vim.cmd("vsplit")

		agent._fullscreen_with_count_explicit("codex", 2, false)

		local inst = agent._get_instance("codex", 2)
		assert.is_not_nil(inst)
		assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
		assert.equals(inst.buf, vim.api.nvim_get_current_buf())
		assert.is_true(agent.agent_fullscreen)
		assert.is_true(vim.b[inst.buf].edgy_disable == true)
		assert.equals("", vim.bo[file_buf].buftype)
		assert.same({ "file contents" }, vim.api.nvim_buf_get_lines(file_buf, 0, -1, false))
	end)

	it("moves a running split instance into fullscreen", function()
		agent.Open("claude", nil, "vsplit", 0)
		local inst = agent._get_instance("claude", 0)
		vim.cmd("wincmd p")
		assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))

		agent._fullscreen_with_count_explicit("claude", 0, false)

		assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
		assert.equals(inst.buf, vim.api.nvim_get_current_buf())
		assert.equals(inst.job_id, agent._get_instance("claude", 0).job_id, "reuses the running job")
		assert.is_true(vim.b[inst.buf].edgy_disable == true)
	end)

	it("rejects an index above 9", function()
		local original = vim.notify
		local notified
		vim.notify = function(msg)
			notified = msg
		end
		agent._fullscreen_with_count_explicit("claude", 10, false)
		vim.notify = original
		assert.is_nil(agent._get_instance("claude", 10))
		assert.is_false(agent.agent_fullscreen)
		assert.is_truthy(notified:find("0%-9"))
	end)

	it("reverts the fullscreen instance, not the default, when a file is opened", function()
		require("tw.agent.commands").setup_autocmds(agent)
		agent.default_mode = "claude"
		agent.Open("claude", nil, "vsplit", 0)
		local default = agent._get_instance("claude", 0)

		agent._fullscreen_with_count_explicit("codex", 1, false)
		local codex = agent._get_instance("codex", 1)

		vim.cmd("enew")
		vim.bo.buftype = ""
		vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() })

		assert.is_true(helpers.buf_visible(codex.buf))
		assert.is_false(helpers.buf_visible(default.buf))
		assert.is_false(vim.b[codex.buf].edgy_disable)
	end)
end)
