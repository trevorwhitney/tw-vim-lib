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

describe("visible_agent_wins / alive_instances", function()
  local agent, claude_mod
  local helpers = require("tests.agent.spec_helpers")

  before_each(function()
    pcall(vim.cmd, "only")
    pcall(vim.cmd, "enew")
    -- Earlier describe blocks leave hidden agent:// buffers behind; a
    -- lingering buffer holding the same agent://mode#idx name makes
    -- Toggle's nvim_buf_set_name fail silently, so delete them first.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match("^agent://") then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    agent, claude_mod = helpers.reset_and_mock(true)
    claude_mod.command = function() return "sleep 30" end
  end)

  after_each(function()
    package.loaded["edgy"] = nil
    for _, _, buf, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
      if buf and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  it("returns each open agent window with parsed mode and idx", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local visible = agent._visible_agent_wins()
    assert.equals(2, #visible)
    local idxs = {}
    for _, entry in ipairs(visible) do
      assert.equals("opencode", entry.mode)
      assert.is_number(entry.win)
      idxs[entry.idx] = true
    end
    assert.is_true(idxs[0])
    assert.is_true(idxs[1])
  end)

  it("excludes closed windows whose buffer is still alive", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    helpers.hide_buffer(agent._get_instance("opencode", 1).buf)
    local visible = agent._visible_agent_wins()
    assert.equals(1, #visible)
    assert.equals(0, visible[1].idx)
  end)

  it("excludes windows whose edgy pane is collapsed", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local inst1 = agent._get_instance("opencode", 1)
    package.loaded["edgy"] = {
      get_win = function(win)
        if vim.api.nvim_win_get_buf(win) == inst1.buf then
          return { visible = false }
        end
        return { visible = true }
      end,
    }
    local visible = agent._visible_agent_wins()
    assert.equals(1, #visible)
    assert.equals(0, visible[1].idx)
  end)

  it("treats windows as visible when edgy get_win errors", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    package.loaded["edgy"] = {
      get_win = function() error("boom") end,
    }
    assert.equals(1, #agent._visible_agent_wins())
  end)

  it("alive_instances lists live jobs and skips dead records", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent._set_instance("pi", 3, nil, nil)
    local alive = agent._alive_instances()
    assert.equals(1, #alive)
    assert.equals("pi", alive[1].mode)
    assert.equals(0, alive[1].idx)
  end)
end)
