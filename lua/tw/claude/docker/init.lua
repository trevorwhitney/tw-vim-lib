local M = {}

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

  if os_type == "Linux" then
    network_flag = "--network host"
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
    table.insert(docker_cmd, source_path .. ":/context/" .. mount_name .. ":ro")
  end

  -- Add the rest of the arguments
  local remaining_args = {
    "-v", vim.fn.getcwd() .. ":/workspace",
    "-v", vim.fn.expand("~/.config/claude-container") .. ":/home/node/.claude",
    "-v", "claude-history:/commandhistory",
    "-e", "NODE_OPTIONS=--max-old-space-size=4096",
    "-e", "CLAUDE_CONFIG_DIR=/home/node/.claude",
    "-e", "ANTHROPIC_API_KEY=" .. (vim.env.ANTHROPIC_API_KEY or ""),
    "-e", "GITHUB_PERSONAL_ACCESS_TOKEN=" .. (vim.env.GITHUB_PERSONAL_ACCESS_TOKEN or ""),
    "-e", "GH_TOKEN=" .. (vim.env.GH_TOKEN or ""),
    "-e", "OPENAI_API_KEY=" .. (vim.env.OPENAI_API_KEY or ""),
    "-e", "TERM=dumb" .. (vim.env.TERM or "xterm-256color"),
    "-e", "COLORTERM=" .. (vim.env.COLORTERM or "truecolor"),
    "-e", "FORCE_COLOR=1",
    "-e", "CLAUDE_INBOX_URL=" .. (vim.env.CLAUDE_INBOX_URL or "http://host.docker.internal:43111/events"),
    "tw-claude-code:latest",
    "tail", "-f", "/dev/null"
  }

  for _, arg in ipairs(remaining_args) do
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
            -- Firewall setup successful
            log.info("Container firewall setup completed successfully")
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
  local check_cmd = "docker exec " .. container_name .. " sudo iptables -L -n | grep -q 'policy DROP'"
  local handle = io.popen(check_cmd .. " 2>/dev/null")
  if handle then
    handle:close()
    return vim.v.shell_error == 0
  end
  return false
end

return M
