local M = {}

M.agent_started = "TwAgentStarted"

function M.very_lazy()
	local argv = vim and vim.v and vim.v.argv or {}
	for _, arg in ipairs(argv) do
		if arg == "+AgentFullscreen" or arg:match("^%+AgentFullscreen%s") then
			return "User " .. M.agent_started
		end
	end

	return "VeryLazy"
end

function M.on_very_lazy(callback)
	local event = M.very_lazy()
	local pattern = event:match("^User%s+(.+)$") or event
	vim.api.nvim_create_autocmd("User", {
		pattern = pattern,
		once = true,
		callback = callback,
	})
end

function M.emit_agent_started()
	vim.api.nvim_exec_autocmds("User", { pattern = M.agent_started })
end

return M
