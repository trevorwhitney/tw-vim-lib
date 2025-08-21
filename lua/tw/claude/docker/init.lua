local M = {}

-- Detect if we're in a git worktree and return worktree info
function M.detect_worktree()
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

          return {
            worktree_dir = vim.fn.getcwd(),
            gitdir = gitdir,
            main_repo = main_repo,
            -- Extract relative path from main repo for container
            container_gitdir = gitdir:gsub("^" .. vim.pesc(main_repo), "/git-root/")
          }
        end
      end
    end
  end

  return nil
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
  local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/docker/init%.lua$")
  return plugin_root
end

function M.build_docker_image()
  local plugin_root = get_plugin_root()
  local docker_dir = plugin_root .. "/lua/tw/claude/docker"
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
  local os_type = vim.loop.os_uname().sysname
  local network_flag = ""
  local ssh_agent_mount = ""
  local ssh_auth_sock = ""

  if os_type == "Linux" then
    network_flag = "--network host"
    -- On Linux, use the host's SSH_AUTH_SOCK directly
    if vim.env.SSH_AUTH_SOCK then
      ssh_agent_mount = vim.env.SSH_AUTH_SOCK
      ssh_auth_sock = vim.env.SSH_AUTH_SOCK
    end
  else
    -- On macOS, use the Docker Desktop SSH agent forwarding
    ssh_agent_mount = "/run/host-services/ssh-auth.sock"
    ssh_auth_sock = "/run/host-services/ssh-auth.sock"
  end

  -- Check if we're in a git worktree
  local worktree_info = M.detect_worktree()
  local worktree_git_file = nil

  if worktree_info then
    -- Create temporary .git file with corrected paths
    worktree_git_file = M.create_worktree_git_file(worktree_info)
  end

  -- Build the docker command for persistent container
  local docker_cmd = {
    "docker", "run", "-d", "--name", container_name,
    "--cap-add", "NET_ADMIN"
  }

  -- Add network flag if it's not empty
  if network_flag ~= "" then
    table.insert(docker_cmd, network_flag)
  end

  -- Add context directory mounts
  for source_path, _ in pairs(context_dirs) do
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
  end

  -- Add worktree-specific mounts if needed
  if worktree_info and worktree_git_file then
    -- Mount the main git repository
    table.insert(docker_cmd, "-v")
    table.insert(docker_cmd, worktree_info.main_repo .. ":/git-root")

    -- Mount the corrected .git file over the workspace .git
    table.insert(docker_cmd, "-v")
    table.insert(docker_cmd, worktree_git_file .. ":/workspace/.git:ro")
  end

  -- Add SSH agent socket mount if available
  if ssh_agent_mount ~= "" then
    table.insert(docker_cmd, "-v")
    table.insert(docker_cmd, ssh_agent_mount .. ":" .. ssh_auth_sock)
  end

  -- Add the rest of the arguments
  local remaining_args = {
    "-v", vim.fn.getcwd() .. ":/workspace",
    "-v", vim.fn.expand("~/.config/claude-container") .. ":/home/node/.claude",
    "-v", "claude-history:/commandhistory",
    "-v", vim.fn.expand("~/.config/git") .. ":/home/node/.config/git:ro",
    "-v", vim.fn.expand("~/.ssh") .. ":/home/node/.ssh:ro",
    "-e", "NODE_OPTIONS=--max-old-space-size=4096",
    "-e", "CLAUDE_CONFIG_DIR=/home/node/.claude",
    "-e", "ANTHROPIC_API_KEY=" .. (vim.env.ANTHROPIC_API_KEY or ""),
    "-e", "GITHUB_PERSONAL_ACCESS_TOKEN=" .. (vim.env.GITHUB_PERSONAL_ACCESS_TOKEN or ""),
    "-e", "GH_TOKEN=" .. (vim.env.GH_TOKEN or ""),
    "-e", "OPENAI_API_KEY=" .. (vim.env.OPENAI_API_KEY or ""),
    "-e", "COLORTERM=" .. (vim.env.COLORTERM or "truecolor"),
    "-e", "FORCE_COLOR=1",
    "-e", "EDITOR=vim",
    "-e", "CLAUDE_INBOX_URL=" .. (vim.env.CLAUDE_INBOX_URL or "http://host.docker.internal:43111/events"),
  }

  -- Add SSH_AUTH_SOCK environment variable if available
  if ssh_auth_sock ~= "" then
    table.insert(remaining_args, "-e")
    table.insert(remaining_args, "SSH_AUTH_SOCK=" .. ssh_auth_sock)
  end

  -- Add remaining arguments to docker command
  for _, arg in ipairs(remaining_args) do
    table.insert(docker_cmd, arg)
  end

  -- Add the container image and command
  local final_args = {
    "tw-claude-code:latest",
    "tail", "-f", "/dev/null"
  }
  for _, arg in ipairs(final_args) do
    table.insert(docker_cmd, arg)
  end

  return table.concat(docker_cmd, " ")
end

function M.start_persistent_container(container_name, context_dirs)
  local cmd = M.get_start_container_command(container_name, context_dirs)
  local handle = io.popen(cmd .. " 2>&1")
  local result = ""
  if handle then
    result = handle:read("*a")
    handle:close()
  end

  return vim.v.shell_error == 0, result
end

function M.attach_to_container(container_name, args)
  container_name = container_name or "claude-code-nvim"
  args = args or ""
  if args ~= "" then
    args = " " .. args
  end

  local cmd = 'docker exec -it ' .. container_name .. ' /bin/bash -c "claude --dangerously-skip-permissions' ..
      args .. '"'
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
              log.info("    - Run :ClaudeDockerBuild to rebuild with fixed firewall script")
              log.info("    - Or check rules with :ClaudeDockerShell and 'sudo iptables -L -n'")
              success = false
            end
          else
            -- Firewall setup failed - container still works but less secure
            log.warn("Container firewall setup failed, exit code: " .. exit_code .. " (container still functional)")
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
  
  -- First check for DROP policies
  local policy_cmd = "docker exec " .. container_name .. " sudo iptables -L -n 2>/dev/null"
  local handle = io.popen(policy_cmd)
  if not handle then
    return false
  end
  
  local output = handle:read("*a")
  handle:close()
  
  -- Check for DROP policies in all chains
  local has_input_drop = output:match("Chain INPUT %(policy DROP%)")
  local has_output_drop = output:match("Chain OUTPUT %(policy DROP%)")
  
  -- Check for problematic catch-all ACCEPT rule in INPUT chain
  -- This pattern matches lines like "ACCEPT     0    --  0.0.0.0/0            0.0.0.0/0"
  -- without any interface specification (which would indicate it's NOT the loopback rule)
  local has_bad_input_rule = false
  for line in output:gmatch("[^\r\n]+") do
    -- Look for ACCEPT all rule without interface specification
    if line:match("^ACCEPT%s+0%s+%-%-%s+0%.0%.0%.0/0%s+0%.0%.0%.0/0%s*$") then
      has_bad_input_rule = true
      break
    end
  end
  
  -- Firewall is properly configured if:
  -- 1. Both INPUT and OUTPUT have DROP policies
  -- 2. There's no catch-all ACCEPT rule in INPUT
  return has_input_drop and has_output_drop and not has_bad_input_rule
end

return M
