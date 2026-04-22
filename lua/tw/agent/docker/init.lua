local M = {}

-- Constants for workspace-mirroring mount strategy
local CONTAINER_HOME = "/home/node"
local CONTAINER_WORKSPACE = CONTAINER_HOME .. "/workspace"

-- Detect if we're in a git worktree and return worktree info.
-- mount_info: result of workspace_mount_info(), used to determine container paths.
--   If nil, falls back to legacy /git-root based paths.
function M.detect_worktree(mount_info)
	local git_path = vim.fn.getcwd() .. "/.git"

	-- Check if .git is a file (worktree indicator)
	if vim.fn.filereadable(git_path) == 1 then
		local file = io.open(git_path, "r")
		if file then
			local content = file:read("*a")
			file:close()

			-- Parse gitdir line
			local gitdir = content:match("gitdir:%s*(.+)")
			if gitdir then
				-- Trim whitespace
				gitdir = gitdir:gsub("^%s+", ""):gsub("%s+$", "")

				-- Get the main repository path (parent of .git/worktrees)
				-- gitdir format: /path/to/repo/.git/worktrees/worktree-name
				local main_repo = gitdir:match("(.+)/%.git/worktrees/[^/]+$")

				if main_repo then
					-- Resolve to absolute path
					main_repo = vim.fn.fnamemodify(main_repo, ":p")

					-- Determine the container gitdir path based on mount strategy
					local container_gitdir
					if mount_info and mount_info.is_workspace_mode then
						-- Main repo is under ~/workspace, rewrite host prefix to container prefix
						local host_ws = mount_info.host_workspace
						container_gitdir = gitdir:gsub("^" .. vim.pesc(host_ws), mount_info.container_workspace)
					else
						-- Fallback: main repo mounted at /git-root
						container_gitdir = gitdir:gsub("^" .. vim.pesc(main_repo), "/git-root/")
					end

					-- Determine where to mount the .git file inside the container
					local container_git_mount_path
					if mount_info and mount_info.is_workspace_mode then
						container_git_mount_path = mount_info.container_cwd .. "/.git"
					else
						container_git_mount_path = CONTAINER_WORKSPACE .. "/.git"
					end

					return {
						worktree_dir = vim.fn.getcwd(),
						gitdir = gitdir,
						main_repo = main_repo,
						container_gitdir = container_gitdir,
						container_git_mount_path = container_git_mount_path,
						-- Track whether main repo needs a separate mount
						needs_git_root_mount = not (mount_info and mount_info.is_workspace_mode),
					}
				end
			end
		end
	end

	return nil
end

-- Determine mount strategy based on whether CWD is under ~/workspace.
-- Returns a table with mount info:
--   host_workspace: expanded ~/workspace path (string)
--   container_workspace: "/home/node/workspace" (string)
--   is_workspace_mode: true if CWD is under ~/workspace (boolean)
--   mount_source: host path to mount (~/workspace or CWD) (string)
--   mount_target: container path to mount at (string)
--   container_cwd: the working directory inside the container (string)
function M.workspace_mount_info()
	local host_workspace = vim.fn.expand("~/workspace")
	-- Ensure no trailing slash for consistent prefix matching
	host_workspace = host_workspace:gsub("/$", "")
	local cwd = vim.fn.getcwd()

	-- Check if CWD is under ~/workspace (equal to it or a subdirectory)
	local is_workspace_mode = cwd == host_workspace or cwd:sub(1, #host_workspace + 1) == host_workspace .. "/"

	if is_workspace_mode then
		-- Derive container CWD by replacing host prefix with container prefix
		local relative = cwd:sub(#host_workspace + 1) -- includes leading "/" or is ""
		local container_cwd = CONTAINER_WORKSPACE .. relative

		return {
			host_workspace = host_workspace,
			container_workspace = CONTAINER_WORKSPACE,
			is_workspace_mode = true,
			mount_source = host_workspace,
			mount_target = CONTAINER_WORKSPACE,
			container_cwd = container_cwd,
		}
	else
		-- Fallback: mount CWD at /home/node/workspace (same as old /workspace behavior)
		return {
			host_workspace = host_workspace,
			container_workspace = CONTAINER_WORKSPACE,
			is_workspace_mode = false,
			mount_source = cwd,
			mount_target = CONTAINER_WORKSPACE,
			container_cwd = CONTAINER_WORKSPACE,
		}
	end
end

-- Create a temporary .git file with corrected paths for container
function M.create_worktree_git_file(worktree_info)
	-- Create temp file with corrected gitdir path
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")
	local temp_git_file = temp_dir .. "/git"

	local file = io.open(temp_git_file, "w")
	if file then
		file:write("gitdir: " .. worktree_info.container_gitdir .. "\n")
		file:close()
		return temp_git_file
	end

	return nil
end

-- Get the plugin root directory
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/agent/docker/init%.lua$")
	return plugin_root
end

function M.build_docker_image()
	local plugin_root = get_plugin_root()
	local docker_dir = plugin_root .. "/lua/tw/agent/docker"
	return "cd " .. docker_dir .. " && docker build -t tw-claude-code:latest ."
end

function M.check_docker_image()
	local handle = io.popen("docker images -q tw-claude-code:latest 2>/dev/null")
	local result = ""
	if handle then
		result = handle:read("*a")
		handle:close()
	end
	return result ~= ""
end

-- Container lifecycle management functions
function M.ensure_container_stopped(container_name)
	container_name = container_name or "claude-code-nvim"
	-- Force remove any existing container with this name
	local cmd = "docker rm -f " .. container_name .. " 2>/dev/null"
	vim.fn.system(cmd)
end

function M.get_start_container_command(container_name, context_dirs)
	container_name = container_name or "claude-code-nvim"
	context_dirs = context_dirs or {}
	local os_type = vim.uv.os_uname().sysname
	local network_flag = ""

	if os_type == "Linux" then
		network_flag = "--network host"
	end

	-- Determine mount strategy
	local mount_info = M.workspace_mount_info()

	-- Check if we're in a git worktree
	local worktree_info = M.detect_worktree(mount_info)
	local worktree_git_file = nil

	if worktree_info then
		-- Create temporary .git file with corrected paths
		worktree_git_file = M.create_worktree_git_file(worktree_info)
	end

	-- Build the docker command for persistent container
	local docker_cmd = {
		"docker",
		"run",
		"-d",
		"--name",
		container_name,
		"--cap-add",
		"NET_ADMIN",
	}

	-- Add network flag if it's not empty
	if network_flag ~= "" then
		table.insert(docker_cmd, network_flag)
	end

	-- Add context directory mounts (skip dirs already under workspace mount)
	for source_path, _ in pairs(context_dirs) do
		-- In workspace mode, skip dirs that are under ~/workspace (already accessible)
		if mount_info.is_workspace_mode then
			local host_ws = mount_info.host_workspace
			local is_under_workspace = source_path == host_ws or source_path:sub(1, #host_ws + 1) == host_ws .. "/"
			if is_under_workspace then
				goto continue_context
			end
		end

		local dir_name = vim.fn.fnamemodify(source_path, ":t")
		-- Ensure unique mount points by using full path hash if duplicate names
		local mount_name = dir_name
		local existing_count = 0
		for other_path, _ in pairs(context_dirs) do
			if other_path ~= source_path and vim.fn.fnamemodify(other_path, ":t") == dir_name then
				existing_count = existing_count + 1
			end
		end
		if existing_count > 0 then
			-- Add a hash suffix for uniqueness
			local hash = vim.fn.sha256(source_path)
			mount_name = dir_name .. "_" .. string.sub(hash, 1, 8)
		end
		table.insert(docker_cmd, "-v")
		table.insert(docker_cmd, source_path .. ":/context/" .. mount_name)

		::continue_context::
	end

	-- Add worktree-specific mounts if needed
	if worktree_info and worktree_git_file then
		-- Only mount the main repo at /git-root if NOT in workspace mode
		if worktree_info.needs_git_root_mount then
			table.insert(docker_cmd, "-v")
			table.insert(docker_cmd, worktree_info.main_repo .. ":/git-root")
		end

		-- Mount the corrected .git file at the appropriate container path
		table.insert(docker_cmd, "-v")
		table.insert(docker_cmd, worktree_git_file .. ":" .. worktree_info.container_git_mount_path .. ":ro")
	end

	-- Add the primary workspace mount and other volume/env arguments
	local remaining_args = {
		"-v",
		mount_info.mount_source .. ":" .. mount_info.mount_target,
		"-v",
		vim.fn.expand("~/.config/claude-container") .. ":/home/node/.claude",
		"-v",
		vim.fn.expand("~/.config/gemini-container") .. ":/home/node/.gemini",
		"-v",
		vim.fn.expand("~/.config/codex-container") .. ":/home/node/.codex",
		"-v",
		vim.fn.expand("~/.config/pi-container") .. ":/home/node/.pi",
		"-v",
		"claude-history:/commandhistory",
		"-v",
		vim.fn.expand("~/.config/git") .. ":/home/node/.config/git:ro",
		"-v",
		vim.fn.expand("~/.ssh") .. ":/home/node/.ssh:ro",
		"-e",
		"NODE_OPTIONS=--max-old-space-size=4096",
		"-e",
		"CLAUDE_CONFIG_DIR=/home/node/.claude",
		"-e",
		"ANTHROPIC_API_KEY=" .. (vim.env.ANTHROPIC_API_KEY or ""),
		"-e",
		"GITHUB_PERSONAL_ACCESS_TOKEN=" .. (vim.env.GITHUB_PERSONAL_ACCESS_TOKEN or ""),
		"-e",
		"GH_TOKEN=" .. (vim.env.GH_TOKEN or ""),
		"-e",
		"OPENAI_API_KEY=" .. (vim.env.OPENAI_API_KEY or ""),
		"-e",
		"COLORTERM=" .. (vim.env.COLORTERM or "truecolor"),
		"-e",
		"FORCE_COLOR=1",
		"-e",
		"EDITOR=vim",
		"-e",
		"CLAUDE_INBOX_URL=" .. (vim.env.CLAUDE_INBOX_URL or "http://host.docker.internal:43111/events"),
	}

	-- Add remaining arguments to docker command
	for _, arg in ipairs(remaining_args) do
		table.insert(docker_cmd, arg)
	end

	-- Add the container image and command
	local final_args = {
		"tw-claude-code:latest",
		"tail",
		"-f",
		"/dev/null",
	}
	for _, arg in ipairs(final_args) do
		table.insert(docker_cmd, arg)
	end

	return table.concat(docker_cmd, " "), mount_info
end

function M.attach_to_container(container_name, args, command, working_dir)
	container_name = container_name or "claude-code-nvim"
	args = args or ""
	command = command or "claude"
	working_dir = working_dir or CONTAINER_WORKSPACE
	if args ~= "" then
		args = " " .. args
	end

	local cmd_string
	if command == "codex" then
		cmd_string = "codex --search --full-auto" .. args
	elseif command == "opencode" then
		cmd_string = "opencode" .. args
	elseif command == "pi" then
		cmd_string = "pi" .. args
	else
		cmd_string = "claude --dangerously-skip-permissions" .. args
	end

	local cmd = "docker exec -it -w " .. working_dir .. " " .. container_name .. ' /bin/bash -c "' .. cmd_string .. '"'
	return cmd
end

function M.is_container_running(container_name)
	container_name = container_name or "claude-code-nvim"
	local cmd = "docker ps -q -f name=" .. container_name .. " 2>/dev/null"
	local handle = io.popen(cmd)
	local result = ""
	if handle then
		result = handle:read("*a")
		handle:close()
	end
	local trimmed_result = result:gsub("%s+", "")

	-- Also check container status for more detailed info
	local status_cmd = "docker ps -a --format '{{.Status}}' -f name=" .. container_name .. " 2>/dev/null"
	local status_handle = io.popen(status_cmd)
	local status = ""
	if status_handle then
		status = status_handle:read("*a"):gsub("%s+", "")
		status_handle:close()
	end

	return trimmed_result ~= "", trimmed_result, status
end

function M.stop_container(container_name)
	container_name = container_name or "claude-code-nvim"
	local cmd = "docker stop " .. container_name .. " 2>/dev/null && docker rm " .. container_name .. " 2>/dev/null"
	vim.fn.system(cmd)
end

function M.setup_container_firewall(container_name, callback)
	container_name = container_name or "claude-code-nvim"
	local firewall_cmd = "docker exec " .. container_name .. " sudo /usr/local/bin/init-firewall.sh"

	vim.fn.jobstart(firewall_cmd, {
		on_exit = function(_, exit_code)
			vim.schedule(function()
				local success = exit_code == 0
				local log = _G.claude_log
				if log then
					if success then
						-- Verify firewall is actually set up correctly
						local verify_success = M.check_firewall_status(container_name)
						if verify_success then
							log.info("Container firewall setup completed and verified successfully")
						else
							log.warn("Firewall script succeeded but verification detected issues:")
							log.warn("⚠️  Either DROP policies are missing or there's a catch-all ACCEPT rule")
							log.info("  - ADVICE:")
							log.info("    - Run :ClaudeDocker build to rebuild with fixed firewall script")
							log.info("    - Or check rules with :ClaudeDocker shell and 'sudo iptables -L -n'")
							success = false
						end
					else
						-- Firewall setup failed - container still works but less secure
						log.warn(
							"Container firewall setup failed, exit code: "
								.. exit_code
								.. " (container still functional)"
						)
					end
				end

				-- Call the callback with success status
				if callback then
					callback(success)
				end
			end)
		end,
		on_stdout = function(_, data)
			if data and #data > 0 then
				local log = _G.claude_log
				for _, line in ipairs(data) do
					if line and line ~= "" and log then
						log.debug("Firewall setup: " .. line)
					end
				end
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 then
				local log = _G.claude_log
				for _, line in ipairs(data) do
					if line and line ~= "" and log then
						log.warn("Firewall setup error: " .. line)
					end
				end
			end
		end,
	})
end

function M.check_firewall_status(container_name)
	container_name = container_name or "claude-code-nvim"
	local log = _G.claude_log

	-- First check for DROP policies (use -v for verbose output with interface info)
	local policy_cmd = "docker exec " .. container_name .. " sudo iptables -L -n -v 2>/dev/null"
	local handle = io.popen(policy_cmd)
	if not handle then
		return false
	end

	local output = handle:read("*a")
	handle:close()

	-- Check for DROP policies in all chains
	-- format is "Chain INPUT (policy DROP 0 packets, 0 bytes)"
	local has_input_drop = output:match("Chain INPUT %(policy DROP")
	local has_output_drop = output:match("Chain OUTPUT %(policy DROP")

	if log then
		log.debug("Firewall status check - INPUT DROP policy: " .. tostring(has_input_drop ~= nil))
		log.debug("Firewall status check - OUTPUT DROP policy: " .. tostring(has_output_drop ~= nil))
	end

	-- Check for problematic catch-all ACCEPT rule in INPUT chain
	-- format is: pkts bytes target prot opt in out source destination
	-- We need to check if there's an ACCEPT rule with "any" or "*" in the "in" column
	-- which means it accepts from any interface (not just loopback)
	local has_bad_input_rule = false
	local in_input_chain = false

	for line in output:gmatch("[^\r\n]+") do
		-- Track which chain we're in
		if line:match("^Chain INPUT") then
			in_input_chain = true
		elseif line:match("^Chain ") then
			in_input_chain = false
		end

		-- Only check rules in INPUT chain
		if in_input_chain then
			-- Format: pkts bytes target prot opt in out source destination [extra]
			-- We want to find ACCEPT rules where "in" is "any" or "*" (meaning any interface)
			local pkts, bytes, target, prot, opt, iface_in, iface_out, source, dest =
				line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")

			if
				target == "ACCEPT"
				and prot == "all"
				and (iface_in == "any" or iface_in == "*")
				and source == "0.0.0.0/0"
				and dest == "0.0.0.0/0"
			then
				-- This is a catch-all ACCEPT rule without interface restriction
				has_bad_input_rule = true
				if log then
					log.debug("Found problematic catch-all ACCEPT rule in INPUT chain")
				end
				break
			end
		end
	end

	if log then
		log.debug("Firewall status check - Bad catch-all ACCEPT rule found: " .. tostring(has_bad_input_rule))
	end

	-- Firewall is properly configured if:
	-- 1. Both INPUT and OUTPUT have DROP policies
	-- 2. There's no catch-all ACCEPT rule in INPUT
	local firewall_ok = has_input_drop and has_output_drop and not has_bad_input_rule

	if log then
		log.debug("Firewall status check - Final result: " .. tostring(firewall_ok))
	end

	return firewall_ok
end

-- Container startup functions (moved from main init.lua)
function M.start_container_async(container_name, auto_build, context_directories, callback)
	local log = _G.claude_log
	if log then
		log.info("Starting Claude container startup process", true)
	end

	-- First build image if needed (async)
	if auto_build and not M.check_docker_image() then
		if log then
			log.info("Docker image not found, starting build process", true)
		end
		local build_cmd = M.build_docker_image()
		if log then
			log.debug("Build command: " .. build_cmd)
		end

		vim.fn.jobstart(build_cmd, {
			on_exit = function(_, exit_code)
				vim.schedule(function()
					if log then
						log.debug("Build process exit code: " .. exit_code)
					end
					if exit_code ~= 0 then
						if log then
							log.error("Failed to build Docker image, exit code: " .. exit_code, true)
						end
						if callback then
							callback(false, "build_failed")
						end
						return
					end
					if log then
						log.info("Docker image built successfully", true)
					end
					-- Now start the container
					M.start_container_after_build(container_name, context_directories, callback)
				end)
			end,
			on_stdout = function(_, data)
				-- Log and show build progress
				if data and #data > 0 then
					for _, line in ipairs(data) do
						if line and line ~= "" then
							if log then
								log.debug("Build output: " .. line)
							end
							print("Build: " .. line)
						end
					end
				end
			end,
			on_stderr = function(_, data)
				if data and #data > 0 then
					for _, line in ipairs(data) do
						if line and line ~= "" and log then
							log.error("Build error: " .. line)
						end
					end
				end
			end,
		})
	else
		if log then
			log.info("Docker image exists, proceeding to container startup")
		end
		-- Image exists, start container directly
		M.start_container_after_build(container_name, context_directories, callback)
	end
end

function M.start_container_after_build(container_name, context_directories, callback)
	local log = _G.claude_log
	if log then
		log.info("Starting container cleanup and startup process")
	end

	-- Ensure any existing container is stopped (async)
	local cleanup_cmd = "docker rm -f " .. container_name .. " 2>/dev/null"
	if log then
		log.debug("Cleanup command: " .. cleanup_cmd)
	end

	vim.fn.jobstart(cleanup_cmd, {
		on_exit = function(_, cleanup_exit_code)
			vim.schedule(function()
				if log then
					log.debug("Cleanup exit code: " .. cleanup_exit_code)
				end
				-- Now start the persistent container
				local start_cmd, mount_info = M.get_start_container_command(container_name, context_directories)
				if log then
					log.debug("Container start command: " .. start_cmd)
				end
				vim.fn.jobstart(start_cmd, {
					on_exit = function(_, exit_code)
						vim.schedule(function()
							if log then
								log.debug("Container start exit code: " .. exit_code)
							end
							if exit_code == 0 then
								-- Container started, but need to verify it's actually running
								vim.defer_fn(function()
									local is_running, container_id, container_status =
										M.is_container_running(container_name)
									if log then
										log.debug("Container verification - running: " .. tostring(is_running))
										log.debug("Container verification - ID: " .. (container_id or "none"))
										log.debug(
											"Container verification - status: " .. (container_status or "unknown")
										)
									end

									if is_running then
										if log then
											log.info("Container verified running, setting up firewall...")
										end

										-- Set up firewall after successful container start
										vim.defer_fn(function()
											if log then
												log.info("Starting container firewall setup...")
											end
											M.setup_container_firewall(container_name, function(firewall_success)
												-- This callback runs after firewall setup (success or failure)
												local security_status = firewall_success and " (secured)"
													or " (limited security)"
												if log then
													log.info("Claude container fully ready" .. security_status, true)
												end
												if callback then
													callback(true, "running", mount_info)
												end
											end)
										end, 2000) -- Wait 2 seconds after container verification to set up firewall
									else
										if log then
											log.error(
												"Container started but is not running - status: "
													.. (container_status or "unknown"),
												true
											)
										end
										if callback then
											callback(false, "not_running")
										end
									end
								end, 1000) -- Wait 1 second for container to fully initialize
							else
								if log then
									log.error("Failed to start Claude container, exit code: " .. exit_code, true)
								end
								if callback then
									callback(false, "start_failed")
								end
							end
						end)
					end,
					on_stdout = function(_, data)
						if data and #data > 0 then
							for _, line in ipairs(data) do
								if line and line ~= "" and log then
									log.debug("Container start output: " .. line)
								end
							end
						end
					end,
					on_stderr = function(_, data)
						if data and #data > 0 then
							for _, line in ipairs(data) do
								if line and line ~= "" and log then
									log.error("Container start error: " .. line)
								end
							end
						end
					end,
				})
			end)
		end,
	})
end

return M
