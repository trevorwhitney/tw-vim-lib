describe("agent command permission flags", function()
	local claude, original_popen, original_executable, original_notify, original_module

	before_each(function()
		original_popen = io.popen
		original_executable = vim.fn.executable
		original_notify = vim.notify
		original_module = package.loaded["tw.agent.claude"]
		io.popen = function(command)
			return {
				read = function()
					return "/bin/" .. command:match("%S+$") .. "\n"
				end,
				close = function() end,
			}
		end
		vim.fn.executable = function()
			return 0
		end
		vim.notify = function() end
		package.loaded["tw.agent.claude"] = nil
		claude = require("tw.agent.claude")
	end)

	after_each(function()
		io.popen = original_popen
		vim.fn.executable = original_executable
		vim.notify = original_notify
		package.loaded["tw.agent.claude"] = original_module
	end)

	for _, args in ipairs({
		{ "--dangerously-bypass-approvals-and-sandbox" },
		{ "--approve-for-me" },
		{ "--yolo" },
		{ "--full-auto" },
		{ "--ask-for-approval", "never" },
		{ "--ask-for-approval=never" },
		{ "-a", "never" },
		{ "-a=never" },
		{ "--sandbox", "read-only" },
		{ "--sandbox=read-only" },
		{ "-s", "read-only" },
		{ "-s=read-only" },
	}) do
		it("preserves explicit Codex policy: " .. table.concat(args, " "), function()
			local original_args = vim.deepcopy(args)
			assert.equals("/bin/codex " .. table.concat(args, " "), claude.command(args, "codex", {}, true))
			assert.same(original_args, args)
		end)
	end

	it("adds Codex automatic approval by default", function()
		assert.equals("/bin/codex --approve-for-me", claude.command({}, "codex", {}, true))
		assert.equals("/bin/codex --approve-for-me", claude.command({}, "codex", {}))
	end)

	it("does not duplicate Claude permission flags", function()
		assert.equals(
			"/bin/claude --dangerously-skip-permissions",
			claude.command({ "--dangerously-skip-permissions" }, "claude", {}, true)
		)
	end)

	it("matches whole flags rather than substrings", function()
		local args = { "--sandbox-extra", "prefix--ask-for-approval=never", "--dangerously-bypass-hook-trust" }
		assert.equals(
			"/bin/codex --approve-for-me " .. table.concat(args, " "),
			claude.command(args, "codex", {}, true)
		)
	end)

	it("keeps automatic permissions disabled when requested", function()
		for _, name in ipairs({ "codex", "claude" }) do
			assert.equals("/bin/" .. name, claude.command({}, name, {}, false))
		end
	end)

	it("preserves opencode arguments and its mini flag", function()
		assert.equals(
			"/bin/opencode --mini --model example --model example",
			claude.command({ "--model", "example", "--model", "example" }, "opencode", {}, true)
		)
	end)
end)
