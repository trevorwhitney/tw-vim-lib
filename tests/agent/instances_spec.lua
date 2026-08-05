describe("agent instance lifecycle (Open / Toggle)", function()
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
    pcall(vim.cmd, "enew")
    pcall(vim.cmd, "only")
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

  it("Toggle hides a fullscreen agent that is the only window", function()
    vim.cmd("only")
    vim.cmd("enew")
    agent.agent_fullscreen = true
    agent.Open("opencode", nil, "current", 0)
    agent.agent_fullscreen = false
    local inst = agent._get_instance("opencode", 0)
    assert.is_true(helpers.buf_visible(inst.buf))
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))

    agent.Toggle("opencode", nil, "vsplit", 0)
    assert.is_false(helpers.buf_visible(inst.buf))
    assert.is_table(agent._get_instance("opencode", 0), "instance should still exist in background")
    assert.equals("none", agent.active_mode)
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
    pcall(vim.cmd, "enew")
    pcall(vim.cmd, "only")
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

  it("bare toggle (count 0) closes the whole drawer when agents are stacked", function()
    vim.cmd("only")
    vim.cmd("enew")
    agent.Open("opencode", nil, "vsplit", 0)
    agent.Open("opencode", nil, "vsplit", 1)
    local i0 = agent._get_instance("opencode", 0)
    local i1 = agent._get_instance("opencode", 1)
    assert.is_true(helpers.buf_visible(i0.buf))
    assert.is_true(helpers.buf_visible(i1.buf))

    agent._toggle_with_count_explicit("opencode", 0, false)

    assert.is_false(helpers.buf_visible(i0.buf))
    assert.is_false(helpers.buf_visible(i1.buf))
    assert.is_table(agent._get_instance("opencode", 0), "instances stay alive in background")
    assert.is_table(agent._get_instance("opencode", 1))
    assert.equals("none", agent.active_mode)
  end)

  it("bare toggle (count 0) opens the default instance when no drawer is open", function()
    vim.cmd("only")
    vim.cmd("enew")
    agent._toggle_with_count_explicit("opencode", 0, false)
    assert.is_table(agent._get_instance("opencode", 0))
    assert.equals("opencode", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  -- count 0 is both "no count" and a typed "0": with the drawer open it closes
  -- the whole drawer rather than toggling only instance 0.
  it("count 0 with an open drawer closes the drawer, not just instance 0", function()
    vim.cmd("only")
    vim.cmd("enew")
    agent.Open("opencode", nil, "vsplit", 0)
    agent.Open("opencode", nil, "vsplit", 1)
    local i0 = agent._get_instance("opencode", 0)
    local i1 = agent._get_instance("opencode", 1)

    agent._toggle_with_count_explicit("opencode", 0, false)

    assert.is_false(helpers.buf_visible(i0.buf))
    assert.is_false(helpers.buf_visible(i1.buf))
  end)
end)
