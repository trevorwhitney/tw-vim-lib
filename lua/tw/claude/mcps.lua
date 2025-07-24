local M = {}

local claude = require("tw.claude.claude")

function M.install_github_mcp(pat)
  if not pat or pat == "" then
    vim.api.nvim_err_writeln("GitHub PAT cannot be empty")
    return
  end

  local json_config = string.format([[{
    "command": "docker",
    "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
    "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": "%s"}
  }]], pat)

  local rmCommand = claude.command({ "mcp", "remove", "github" })
  local command = claude.command({ "mcp", "add-json", "github" }) .. " '" .. json_config .. "'"
  local github_cmd = table.concat({ rmCommand, command }, "|| true &&")
  local stderr_data = {}
  vim.fn.jobstart(github_cmd, {
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_data, line)
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.schedule(function()
          vim.api.nvim_echo({ { "GitHub MCP installed successfully", "Normal" } }, false, {})
        end)
      else
        vim.schedule(function()
          local error_msg = "Failed to install GitHub MCP: exit code " .. code
          if #stderr_data > 0 then
            error_msg = error_msg .. "\nError: " .. table.concat(stderr_data, "\n")
          end
          vim.api.nvim_err_writeln(error_msg)
        end)
      end
    end
  })
end

function M.install_zen_mcp(openAiKey)
  if not openAiKey or openAiKey == "" then
    vim.api.nvim_err_writeln("OpenAI API key cannot be empty")
    return
  end

  local json_config = string.format([[{
      "command": "sh",
      "args": [
        "-c",
        "uvx --from git+https://github.com/BeehiveInnovations/zen-mcp-server.git zen-mcp-server"
      ],
      "env": {
        "PATH": "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:~/.local/bin",
        "OPENAI_API_KEY": "%s"
      }
    }]], openAiKey)

  local rmCommand = claude.command({ "mcp", "remove", "zen" })
  local command = claude.command({ "mcp", "add-json", "zen" }) .. " '" .. json_config .. "'"
  local github_cmd = table.concat({ rmCommand, command }, " || true &&")

  local stderr_data = {}
  vim.fn.jobstart(github_cmd, {
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_data, line)
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.schedule(function()
          vim.api.nvim_echo({ { "Zen MCP installed successfully", "Normal" } }, false, {})
        end)
      else
        vim.schedule(function()
          local error_msg = "Failed to install Zen MCP: exit code " .. code
          if #stderr_data > 0 then
            error_msg = error_msg .. "\nError: " .. table.concat(stderr_data, "\n")
          end
          vim.api.nvim_err_writeln(error_msg)
        end)
      end
    end
  })
end

function M.install_mcps()
  vim.api.nvim_create_user_command("InstallGithubMCP", function(opts)
    M.install_github_mcp(opts.args)
  end, {
    nargs = 1,
    desc = "Setup GitHub MCP with GitHub Personal Access Token",
  })
  vim.api.nvim_create_user_command("InstallZenMCP", function(opts)
    M.install_zen_mcp(opts.args)
  end, {
    nargs = 1,
    desc = "Setup Zen MCP with OpenAI API key",
  })
end

return M
