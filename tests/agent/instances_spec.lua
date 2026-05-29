describe("agent instance lifecycle (Open / Toggle / close_other_agent_buffers)", function()
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
    assert.is_true(helpers.buf_visible(inst.buf))
  end)

  it("Toggle on a visible instance hides it and resets active state", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.is_false(helpers.buf_visible(inst.buf))
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
    assert.is_table(agent._get_instance("pi", 0), "instance should still exist in background")
  end)

  it("Toggle on a hidden but alive instance shows it again", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 0)  -- hide
    agent.Toggle("pi", nil, "vsplit", 0)  -- show
    assert.is_true(helpers.buf_visible(inst.buf))
    assert.equals("pi", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  it("Toggle(pi, 1) hides pi#0 (same mode, different idx)", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local p0 = agent._get_instance("pi", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    local p1 = agent._get_instance("pi", 1)
    assert.is_false(helpers.buf_visible(p0.buf))
    assert.is_true(helpers.buf_visible(p1.buf))
    assert.equals(1, agent.active_index)
  end)

  it("Toggle(pi, 0) hides opencode#0 (cross-mode)", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    local oc = agent._get_instance("opencode", 0)
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.is_false(helpers.buf_visible(oc.buf))
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

describe("toggle_with_count wrappers", function()
  local helpers = require("tests.agent.spec_helpers")
  local agent, claude_mod

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    claude_mod.command = function() return "sleep 30" end
  end)

  after_each(function()
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
  end)

  it("_toggle_with_count_explicit(pi, 0, false) toggles pi#0", function()
    agent._toggle_with_count_explicit("pi", 0, false)
    assert.is_table(agent._get_instance("pi", 0))
    assert.equals("pi", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  it("_toggle_with_count_explicit(pi, 3, false) toggles pi#3", function()
    agent._toggle_with_count_explicit("pi", 3, false)
    assert.is_table(agent._get_instance("pi", 3))
    assert.equals(3, agent.active_index)
  end)

  it("_toggle_with_count_explicit(pi, 10, false) notifies and does nothing", function()
    local notified
    local original = vim.notify
    vim.notify = function(msg, _) notified = msg end
    agent._toggle_with_count_explicit("pi", 10, false)
    vim.notify = original
    assert.is_nil(agent._get_instance("pi", 10))
    assert.is_string(notified)
    assert.is_truthy(notified:find("0%-9"))
  end)

  it("_toggle_with_count_explicit in visual mode forces idx 0", function()
    agent._toggle_with_count_explicit("pi", 5, true)
    assert.is_table(agent._get_instance("pi", 0))
    assert.is_nil(agent._get_instance("pi", 5))
  end)

  it("_toggle_with_count_explicit(opencode, 2, false) toggles opencode#2", function()
    agent._toggle_with_count_explicit("opencode", 2, false)
    assert.is_table(agent._get_instance("opencode", 2))
    assert.equals("opencode", agent.active_mode)
    assert.equals(2, agent.active_index)
  end)
end)
