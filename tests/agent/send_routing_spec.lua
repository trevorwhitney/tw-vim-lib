describe("resolve_send_target", function()
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

  it("count=0 with active returns (active_mode, active_index)", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    local mode, idx = agent._resolve_send_target(0)
    assert.equals("opencode", mode)
    assert.equals(0, idx)
  end)

  it("count=0 with no active spawns default_mode at idx 0", function()
    agent.default_mode = "pi"
    local mode, idx = agent._resolve_send_target(0)
    assert.equals("pi", mode)
    assert.equals(0, idx)
    assert.is_table(agent._get_instance("pi", 0))
  end)

  it("count>0 with active opencode spawns opencode#N", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    local mode, idx = agent._resolve_send_target(3)
    assert.equals("opencode", mode)
    assert.equals(3, idx)
    assert.is_table(agent._get_instance("opencode", 3))
  end)

  it("count>0 with active_mode='none' uses default_mode (not literal 'none')", function()
    -- Defense against the Lua truthy-string bug: M.active_mode or M.default_mode
    -- evaluates to "none" since strings are truthy. The implementation must use
    -- an explicit ternary.
    agent.default_mode = "pi"
    local mode, idx = agent._resolve_send_target(2)
    assert.equals("pi", mode)
    assert.equals(2, idx)
  end)

  it("count>9 returns nil and notifies", function()
    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, _) notified = msg end
    local mode, idx = agent._resolve_send_target(10)
    vim.notify = original_notify
    assert.is_nil(mode); assert.is_nil(idx)
    assert.is_string(notified)
    assert.is_truthy(notified:find("0%-9"))
  end)
end)

describe("send routing end-to-end via _send_with_count", function()
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

  it("SendText with idx=0 (active) routes to the active instance's job_id", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local sent_to_job, sent_text
    local real = vim.fn.chansend
    vim.fn.chansend = function(job, text)
      sent_to_job, sent_text = job, text
      return 1
    end
    agent._send_with_count("SendText", 0, "hello", false)
    vim.fn.chansend = real
    assert.equals(agent._get_instance("pi", 0).job_id, sent_to_job)
    assert.equals("hello", sent_text)
  end)

  it("SendText with idx=2 spawns pi#2 and routes to it", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local sent_to_job
    local real = vim.fn.chansend
    vim.fn.chansend = function(job, _) sent_to_job = job; return 1 end
    agent._send_with_count("SendText", 2, "hi", false)
    -- confirmOpenAndDo defers send by ~2500ms after spawn
    vim.wait(3000, function()
      return sent_to_job ~= nil
    end)
    vim.fn.chansend = real
    local p2 = agent._get_instance("pi", 2)
    assert.is_table(p2, "pi#2 should have been spawned")
    assert.equals(p2.job_id, sent_to_job)
  end)
end)
