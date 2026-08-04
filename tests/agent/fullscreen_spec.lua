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
