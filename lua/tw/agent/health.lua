local M = {}
local health = require("vim.health")

M.check = function()
	-- Check environment variables
	health.start("Environment Configuration")

	if vim.env.ANTHROPIC_API_KEY then
		health.ok("ANTHROPIC_API_KEY is set")
	else
		health.error("ANTHROPIC_API_KEY not set", "Export ANTHROPIC_API_KEY environment variable")
	end

	-- Check agent mode settings
	health.start("AI Agent Mode Settings")

	local agent = require("tw.agent")
	health.ok("Default mode: " .. agent.default_mode)
end

return M
