describe("commands.lua flat-field migration", function()
  local helpers = require("tests.agent.spec_helpers")
  local agent, claude_mod, commands

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    agent.default_mode = "pi"  -- Set default_mode to pi for these tests
    package.loaded["tw.agent.commands"] = nil
    commands = require("tw.agent.commands")
    claude_mod.command = function() return "sleep 30" end
  end)

  after_each(function()
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
  end)

  it("resolve_default_agent_buf finds the default-mode instance via get_instance", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.equals(agent._get_instance("pi", 0).buf, commands._resolve_default_agent_buf())
  end)

  it("resolve_default_agent_buf returns nil when no default-mode instance exists", function()
    -- Spawn an opencode instance, but default is "pi" — should return nil
    agent.Toggle("opencode", nil, "vsplit", 0)
    assert.is_nil(commands._resolve_default_agent_buf())
  end)

  it("is_agent_buf returns true for any instance buf, including idx > 0", function()
    agent.Toggle("pi", nil, "vsplit", 1)
    local inst = agent._get_instance("pi", 1)
    assert.is_true(commands._is_agent_buf(inst.buf))
  end)

  it("is_agent_buf returns false for unrelated buffers", function()
    local scratch = vim.api.nvim_create_buf(false, true)
    assert.is_false(commands._is_agent_buf(scratch))
    pcall(vim.api.nvim_buf_delete, scratch, { force = true })
  end)
end)

describe("updatetime optimization (direct call + agent:// TermClose)", function()
  local helpers = require("tests.agent.spec_helpers")
  local agent, claude_mod, commands

  before_each(function()
    agent, claude_mod = helpers.reset_and_mock(true)
    agent.default_mode = "pi"  -- Set default_mode to pi for these tests
    package.loaded["tw.agent.commands"] = nil
    commands = require("tw.agent.commands")
    commands.setup_autocmds(agent)  -- Register autocmds for this test
    claude_mod.command = function() return "sleep 30" end
    vim.o.updatetime = 4000
    agent.saved_updatetime = nil
  end)

  after_each(function()
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
    vim.o.updatetime = 4000
    agent.saved_updatetime = nil
  end)

  it("opening pi#0 shortens updatetime immediately via direct call", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    assert.is_true(vim.o.updatetime < 4000,
      "updatetime should be reduced after spawn; was " .. vim.o.updatetime)
    assert.equals(4000, agent.saved_updatetime,
      "previous updatetime should be saved for later restore")
  end)

  it("TermClose on the last agent buffer restores updatetime", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    assert.is_true(vim.o.updatetime < 4000, "sanity: updatetime should be reduced")

    vim.fn.jobstop(inst.job_id)
    -- Wait for the OnExit callback to clear the instance AND the TermClose
    -- autocmd to fire (which restores updatetime via the helper).
    vim.wait(2000, function()
      return agent._get_instance("pi", 0) == nil and vim.o.updatetime == 4000
    end)

    assert.is_nil(agent._get_instance("pi", 0),
      "instance should be cleared by OnExit after jobstop")
    assert.equals(4000, vim.o.updatetime,
      "TermClose autocmd should have restored updatetime")
  end)
end)
