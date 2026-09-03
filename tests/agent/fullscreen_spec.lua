local helpers = require("tests.agent.spec_helpers")

describe("fullscreen edgy opt-out", function()
  local agent, claude_mod

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    claude_mod.command = function() return "sleep 30" end
    pcall(vim.cmd, "enew")
  end)

  after_each(function()
    agent.agent_fullscreen = false
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
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
  local agent, claude_mod, captured

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    captured = nil
    claude_mod.command = function(args)
      captured = args
      return "sleep 30"
    end
    pcall(vim.cmd, "enew")
  end)

  after_each(function()
    agent.agent_fullscreen = false
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
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

  it("passes no extra args when none are given", function()
    agent.OpenFullscreen("opencode")
    wait_for_command()

    assert.is_not_nil(captured)
    -- Only the project root that start_new_agent_job prepends for opencode.
    assert.equals(1, #captured)
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
