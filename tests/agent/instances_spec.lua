describe("agent instance lifecycle (Open / Toggle / close_other_agent_buffers)", function()
  local agent, claude_mod

  before_each(function()
    package.loaded["tw.agent"]        = nil
    package.loaded["tw.agent.claude"] = nil
    package.loaded["tw.log"]          = nil
    -- Mock tw.log so requiring tw.agent and tw.agent.claude doesn't hit the real log setup
    -- (which can fail to create its cache directory in the test sandbox).
    package.loaded["tw.log"] = {
      info  = function() end,
      warn  = function() end,
      error = function() end,
      debug = function() end,
    }
    agent      = require("tw.agent")
    claude_mod = require("tw.agent.claude")
    -- Stub the agent command so jobstart spawns a benign long-running process
    claude_mod.command = function() return "sleep 30" end
    -- Reset state explicitly (active_mode now initializes to "none")
    for mode, _ in pairs(agent.instances) do agent.instances[mode] = {} end
    agent.active_mode, agent.active_index = "none", 0
    agent.active_buf, agent.active_job_id = nil, nil
  end)

  after_each(function()
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
  end)

  local function buf_visible(buf)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then return true end
    end
    return false
  end

  it("Open writes to instances[mode][idx]", function()
    agent.Open("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    assert.is_table(inst)
    assert.is_number(inst.buf)
    assert.is_number(inst.job_id)
  end)

  it("Open(_, _, _, 1) creates an independent instance from idx 0", function()
    agent.Open("pi", nil, "vsplit", 0)
    agent.Open("pi", nil, "vsplit", 1)
    local i0 = agent._get_instance("pi", 0)
    local i1 = agent._get_instance("pi", 1)
    assert.is_table(i0); assert.is_table(i1)
    assert.are_not.equals(i0.buf, i1.buf)
    assert.are_not.equals(i0.job_id, i1.job_id)
  end)

  it("Open sets the buffer name to agent://<mode>#<idx>", function()
    agent.Open("pi", nil, "vsplit", 2)
    local inst = agent._get_instance("pi", 2)
    assert.equals("agent://pi#2", vim.api.nvim_buf_get_name(inst.buf))
  end)

  it("Open sets active_mode and active_index", function()
    agent.Open("pi", nil, "vsplit", 3)
    assert.equals("pi", agent.active_mode)
    assert.equals(3, agent.active_index)
  end)

  it("Toggle first time spawns and shows", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    assert.is_table(inst)
    assert.is_true(buf_visible(inst.buf))
  end)

  it("Toggle on a visible instance hides it and resets active state", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.is_false(buf_visible(inst.buf))
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
    assert.is_table(agent._get_instance("pi", 0), "instance should still exist in background")
  end)

  it("Toggle on a hidden but alive instance shows it again", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 0)  -- hide
    agent.Toggle("pi", nil, "vsplit", 0)  -- show
    assert.is_true(buf_visible(inst.buf))
    assert.equals("pi", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  it("Toggle(pi, 1) hides pi#0 (same mode, different idx)", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local p0 = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    local p1 = agent._get_instance("pi", 1)
    assert.is_false(buf_visible(p0.buf))
    assert.is_true(buf_visible(p1.buf))
    assert.equals(1, agent.active_index)
  end)

  it("Toggle(pi, 0) hides opencode#0 (cross-mode)", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    local oc = agent._get_instance("opencode", 0)
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.is_false(buf_visible(oc.buf))
  end)

  it("OnExit clears the instance and resets active state if it was active", function()
    agent.Open("pi", nil, "vsplit", 1)
    local inst = agent._get_instance("pi", 1)
    assert.equals("pi", agent.active_mode); assert.equals(1, agent.active_index)
    vim.fn.jobstop(inst.job_id)
    vim.wait(500, function() return agent._get_instance("pi", 1) == nil end)
    assert.is_nil(agent._get_instance("pi", 1))
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
    assert.is_nil(agent.active_buf)
    assert.is_nil(agent.active_job_id)
  end)

  it("OnExit for a non-active instance does NOT clear active state", function()
    agent.Open("pi", nil, "vsplit", 0)
    agent.Open("pi", nil, "vsplit", 1)
    -- pi#1 is now active
    local i0 = agent._get_instance("pi", 0)
    vim.fn.jobstop(i0.job_id)
    vim.wait(500, function() return agent._get_instance("pi", 0) == nil end)
    assert.is_nil(agent._get_instance("pi", 0))
    assert.equals("pi", agent.active_mode, "active mode should still be pi")
    assert.equals(1, agent.active_index, "active index should still be 1")
  end)
end)
