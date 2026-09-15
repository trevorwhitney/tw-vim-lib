local M = {}
local health = require("vim.health")

M.check = function()
	-- Check agent mode settings
	health.start("AI Agent Mode Settings")

	local agent = require("tw.agent")
	health.ok("Default mode: " .. agent.default_mode)
end

return M
