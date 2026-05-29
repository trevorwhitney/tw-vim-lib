describe("agent instance helpers", function()
  local agent
  local helpers = require("tests.agent.spec_helpers")

  before_each(function()
    agent = helpers.reset_and_mock(false)
  end)

  it("declares an instances table for every supported mode", function()
    for _, mode in ipairs({
      "pi", "opencode", "claude", "codex",
    }) do
      assert.is_table(agent.instances[mode], "missing instances entry for " .. mode)
    end
  end)

  it("active_mode initializes to 'none' and active_index to 0", function()
    assert.equals("none", agent.active_mode)
    assert.equals(0, agent.active_index)
  end)

  it("get_instance returns nil for unknown idx", function()
    assert.is_nil(agent._get_instance("pi", 0))
  end)

  it("set_instance / get_instance round-trip", function()
    agent._set_instance("pi", 1, 42, 99)
    local inst = agent._get_instance("pi", 1)
    assert.is_table(inst)
    assert.equals(42, inst.buf)
    assert.equals(99, inst.job_id)
  end)

  it("set_instance does NOT write legacy flat fields (no dual-write)", function()
    agent._set_instance("pi", 0, 7, 8)
    assert.is_nil(agent.pi_buf, "legacy flat field should not be populated")
    assert.is_nil(agent.pi_job_id, "legacy flat field should not be populated")
  end)

  it("clear_instance removes the entry", function()
    agent._set_instance("pi", 1, 42, 99)
    agent._clear_instance("pi", 1)
    assert.is_nil(agent._get_instance("pi", 1))
  end)

  it("iter_all_instances yields every recorded instance in sorted order", function()
    agent._set_instance("pi", 1, 11, 111)
    agent._set_instance("pi", 0, 10, 110)
    agent._set_instance("opencode", 0, 20, 220)
    local seen = {}
    for mode, idx, buf, job_id in agent._iter_all_instances() do
      table.insert(seen, string.format("%s#%d=%d,%d", mode, idx, buf, job_id))
    end
    assert.same({
      "opencode#0=20,220",
      "pi#0=10,110",
      "pi#1=11,111",
    }, seen)
  end)
end)
