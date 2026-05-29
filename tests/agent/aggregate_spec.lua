describe("aggregate operations", function()
  local agent, claude_mod
  local helpers = require("tests.agent.spec_helpers")

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    claude_mod.command = function() return "sleep 30" end
  end)

  after_each(function()
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
  end)

  it("hide_all_agent_buffers hides every instance's window and resets active state", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    agent.hide_all_agent_buffers()
    for _, _, buf, _ in agent._iter_all_instances() do
      assert.is_false(helpers.buf_visible(buf))
    end
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  it("get_status returns mode and index", function()
    agent.Toggle("pi", nil, "vsplit", 2)
    local status = agent.get_status()
    assert.equals("pi", status.mode)
    assert.equals(2, status.index)
  end)

  it("get_status returns mode=none, index=0 when nothing active", function()
    local status = agent.get_status()
    assert.equals("none", status.mode)
    assert.equals(0, status.index)
  end)

  it("restart_local_agent targets the active instance only", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    -- pi#1 is now the active instance (Toggle of pi#1 makes it active and hides pi#0)
    local i0_job_before = agent._get_instance("pi", 0).job_id
    local i1_job_before = agent._get_instance("pi", 1).job_id
    assert.equals("pi", agent.active_mode)
    assert.equals(1, agent.active_index)

    assert.is_true(agent.restart_local_agent())
    -- Wait for the restart to complete: pi#1's slot must hold a new job_id
    vim.wait(2000, function()
      local inst = agent._get_instance("pi", 1)
      return inst and inst.job_id and inst.job_id ~= i1_job_before
    end)

    -- pi#1 (active) should have a new job_id after restart
    local i1_after = agent._get_instance("pi", 1)
    assert.is_table(i1_after, "pi#1 should still exist after restart")
    assert.are_not.equals(i1_job_before, i1_after.job_id, "pi#1 should have new job_id")

    -- pi#0 should be untouched: same job_id, still alive
    local i0_after = agent._get_instance("pi", 0)
    assert.is_table(i0_after, "pi#0 should still exist (not touched by restart)")
    assert.equals(i0_job_before, i0_after.job_id, "pi#0 job_id should be unchanged")
  end)

  it("restart_local_agent returns false when no local instance exists", function()
    assert.is_false(agent.restart_local_agent())
  end)

  it("cleanup stops every job and empties the instances table", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.cleanup()
    for mode, _ in pairs(agent.instances) do
      assert.same({}, agent.instances[mode])
    end
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)
end)
