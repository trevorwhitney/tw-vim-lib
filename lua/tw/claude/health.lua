local M = {}
local health = require("vim.health")
local docker = require("tw.claude.docker")

M.check = function()
	health.start("Claude Docker Container")

	-- Check Docker availability
	if vim.fn.executable("docker") == 1 then
		health.ok("Docker executable found")
	else
		health.error("Docker not found", "Install Docker from https://docker.com")
		return
	end

	-- Check Docker image
	if docker.check_docker_image() then
		health.ok("Docker image 'tw-claude-code:latest' exists")
	else
		health.warn("Docker image not built", "Run :ClaudeDockerBuild to build the image")
	end

	-- Check container status
	local claude = require("tw.claude")
	local container_name = claude.container_name
	local is_running, container_id, status = docker.is_container_running(container_name)

	if is_running then
		health.ok("Container '" .. container_name .. "' is running")

		-- Check firewall configuration
		if docker.check_firewall_status(container_name) then
			health.ok("Container firewall is configured (DROP policies active)")

			-- Verify firewall blocks unauthorized traffic
			local test_cmd = "docker exec "
				.. container_name
				.. " timeout 2 curl -s -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null"
			local handle = io.popen(test_cmd)
			if handle then
				local result = handle:read("*a")
				handle:close()

				if result == "" or result == "000" then
					health.ok("Firewall blocking test passed (unauthorized domain blocked)")
				else
					health.warn(
						"Firewall may not be blocking properly",
						"Check firewall rules with :ClaudeDockerShell and 'sudo iptables -L -n'"
					)
				end
			else
				health.info("Could not test firewall blocking")
			end
		else
			health.warn("Container firewall not configured", "Firewall will be set up on next container start")
		end
	else
		if status and status ~= "" then
			health.info("Container exists but not running (status: " .. status .. ")")
		else
			health.info("No container running")
		end
	end

	-- Check environment variables
	health.start("Environment Configuration")

	if vim.env.ANTHROPIC_API_KEY then
		health.ok("ANTHROPIC_API_KEY is set")
	else
		health.error("ANTHROPIC_API_KEY not set", "Export ANTHROPIC_API_KEY environment variable")
	end

	if vim.env.GH_TOKEN or vim.env.GITHUB_PERSONAL_ACCESS_TOKEN then
		health.ok("GitHub token configured")
	else
		health.warn("No GitHub token found", "Set GH_TOKEN or GITHUB_PERSONAL_ACCESS_TOKEN for GitHub operations")
	end

	-- Check mode settings
	health.start("Claude Mode Settings")

	if claude.docker_mode then
		health.ok("Docker mode enabled")
		if claude.auto_build then
			health.ok("Auto-build enabled (will build image if missing)")
		else
			health.info("Auto-build disabled (manual build required)")
		end
	else
		health.info("Native mode enabled (not using Docker)")
	end

	if claude.auto_prompt and claude.auto_prompt_file then
		health.ok("Auto-prompt enabled: " .. claude.auto_prompt_file)
	else
		health.info("Auto-prompt disabled")
	end
end

return M
