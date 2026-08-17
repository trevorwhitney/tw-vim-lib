describe("resolve_send_target", function()
  local agent, claude_mod
  local helpers = require("tests.agent.spec_helpers")

  -- Run the CPS resolver and return what it reported (or nil if never called).
  local function resolve(count)
    local mode, idx
    agent._resolve_send_target(count, function(m, i)
      mode, idx = m, i
    end)
    return mode, idx
  end

  local function win_showing(buf)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then return win end
    end
  end

  before_each(function()
    pcall(vim.cmd, "only")
    pcall(vim.cmd, "enew")
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
    package.loaded["tw.agent.window_picker"] = nil
    for _, _, _, job_id in agent._iter_all_instances() do
      if job_id then pcall(vim.fn.jobstop, job_id) end
    end
  end)

  it("count=0 with one visible window targets it despite stale active state", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    helpers.hide_buffer(agent._get_instance("opencode", 1).buf)
    assert.equals(1, agent.active_index, "precondition: active state is stale")
    local mode, idx = resolve(0)
    assert.equals("opencode", mode)
    assert.equals(0, idx)
  end)

  it("count=0 with multiple visible windows delegates to the window picker", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local inst0 = agent._get_instance("opencode", 0)
    local labeled
    package.loaded["tw.agent.window_picker"] = {
      pick = function(wins, cb)
        labeled = wins
        cb(win_showing(inst0.buf))
      end,
    }
    local mode, idx = resolve(0)
    assert.equals(2, #labeled)
    assert.equals("opencode", mode)
    assert.equals(0, idx)
  end)

  it("count=0 picker cancel never invokes on_target", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    package.loaded["tw.agent.window_picker"] = {
      pick = function(_, cb) cb(nil) end,
    }
    local mode = resolve(0)
    assert.is_nil(mode)
  end)

  it("count=0 with no visible windows and one alive instance targets it", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    helpers.hide_buffer(agent._get_instance("pi", 0).buf)
    agent.active_mode, agent.active_index = "none", 0
    local mode, idx = resolve(0)
    assert.equals("pi", mode)
    assert.equals(0, idx)
  end)

  it("count=0 with no visible windows and several alive prompts via vim.ui.select", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    helpers.hide_buffer(agent._get_instance("pi", 0).buf)
    helpers.hide_buffer(agent._get_instance("pi", 1).buf)
    local items
    local orig_select = vim.ui.select
    vim.ui.select = function(list, _, cb)
      items = list
      cb(list[2])
    end
    local mode, idx = resolve(0)
    vim.ui.select = orig_select
    assert.equals(2, #items)
    assert.equals("pi", mode)
    assert.equals(1, idx)
  end)

  it("count=0 select cancel never invokes on_target", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    helpers.hide_buffer(agent._get_instance("pi", 0).buf)
    helpers.hide_buffer(agent._get_instance("pi", 1).buf)
    local orig_select = vim.ui.select
    vim.ui.select = function(_, _, cb) cb(nil) end
    local mode = resolve(0)
    vim.ui.select = orig_select
    assert.is_nil(mode)
  end)

  it("count=0 with nothing visible or alive targets default_mode#0 without spawning", function()
    agent.default_mode = "pi"
    local mode, idx = resolve(0)
    assert.equals("pi", mode)
    assert.equals(0, idx)
    assert.is_nil(agent._get_instance("pi", 0), "resolver must not spawn")
  end)

  it("count>0 selects (active_mode, count) without spawning", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    local mode, idx = resolve(3)
    assert.equals("opencode", mode)
    assert.equals(3, idx)
    assert.is_nil(agent._get_instance("opencode", 3), "resolver must not spawn")
  end)

  it("count>0 with active_mode='none' uses default_mode (not literal 'none')", function()
    -- Defense against the Lua truthy-string bug: `M.active_mode or
    -- M.default_mode` evaluates to "none" since strings are truthy. The
    -- implementation must use an explicit ternary.
    agent.default_mode = "pi"
    local mode, idx = resolve(2)
    assert.equals("pi", mode)
    assert.equals(2, idx)
  end)

  it("count>9 notifies and never invokes on_target", function()
    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, _) notified = msg end
    local mode = resolve(10)
    vim.notify = original_notify
    assert.is_nil(mode)
    assert.is_string(notified)
    assert.is_truthy(notified:find("0%-9"))
  end)
end)

describe("send routing end-to-end via _send_with_count", function()
  local agent, claude_mod
  local helpers = require("tests.agent.spec_helpers")

  before_each(function()
    pcall(vim.cmd, "only")
    pcall(vim.cmd, "enew")
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
    package.loaded["tw.agent.window_picker"] = nil
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

  -- Spy on chansend for the duration of fn, returning what was sent where.
  local function with_chansend_spy(fn)
    local sent_to_job, sent_text
    local real = vim.fn.chansend
    vim.fn.chansend = function(job, text)
      sent_to_job, sent_text = job, text
      return 1
    end
    local ok, err = pcall(fn)
    vim.fn.chansend = real
    assert(ok, err)
    return sent_to_job, sent_text
  end

  it("routes count-less sends to the remaining visible agent after one is closed (reported bug)", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local inst0 = agent._get_instance("opencode", 0)
    local inst1 = agent._get_instance("opencode", 1)
    helpers.hide_buffer(inst1.buf)
    assert.equals(1, agent.active_index, "precondition: active state is stale")
    package.loaded["tw.agent.window_picker"] = {
      pick = function() error("picker must not fire with one visible window") end,
    }

    local sent_to_job, sent_text = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)

    assert.equals(inst0.job_id, sent_to_job)
    assert.equals("hello", sent_text)
    assert.is_false(helpers.buf_visible(inst1.buf), "hidden agent must not reopen")
  end)

  it("routes count-less sends past an edgy-collapsed pane", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local inst0 = agent._get_instance("opencode", 0)
    local inst1 = agent._get_instance("opencode", 1)
    package.loaded["edgy"] = {
      get_win = function(win)
        if vim.api.nvim_win_get_buf(win) == inst1.buf then
          return { visible = false }
        end
        return { visible = true }
      end,
    }
    package.loaded["tw.agent.window_picker"] = {
      pick = function() error("picker must not fire with one visible pane") end,
    }

    local sent_to_job = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)

    assert.equals(inst0.job_id, sent_to_job)
  end)

  it("sends to the picker's chosen window when several are visible", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    local inst0 = agent._get_instance("opencode", 0)
    package.loaded["tw.agent.window_picker"] = {
      pick = function(wins, cb)
        for _, win in ipairs(wins) do
          if vim.api.nvim_win_get_buf(win) == inst0.buf then
            cb(win)
            return
          end
        end
        cb(nil)
      end,
    }

    local sent_to_job = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)

    assert.equals(inst0.job_id, sent_to_job)
  end)

  it("reopens the single alive session when nothing is visible", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local inst = agent._get_instance("pi", 0)
    helpers.hide_buffer(inst.buf)
    agent.active_mode, agent.active_index = "none", 0

    local sent_to_job = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)

    assert.equals(inst.job_id, sent_to_job)
    assert.is_true(helpers.buf_visible(inst.buf), "session reopens to receive the send")
  end)

  it("routes via vim.ui.select when several hidden sessions are alive", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    agent.Toggle("pi", nil, "vsplit", 1)
    helpers.hide_buffer(agent._get_instance("pi", 0).buf)
    helpers.hide_buffer(agent._get_instance("pi", 1).buf)
    local inst1 = agent._get_instance("pi", 1)
    local orig_select = vim.ui.select
    vim.ui.select = function(list, _, cb) cb(list[2]) end

    local sent_to_job = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)
    vim.ui.select = orig_select

    assert.equals(inst1.job_id, sent_to_job)
    assert.is_true(helpers.buf_visible(inst1.buf))
  end)

  it("spawns default_mode#0 when nothing is visible or alive", function()
    agent.default_mode = "pi"

    local sent_to_job
    local real = vim.fn.chansend
    vim.fn.chansend = function(job, _)
      sent_to_job = job
      return 1
    end
    agent._send_with_count("SendText", 0, "hello", false)
    -- confirmOpenAndDo defers the send ~2500ms after a fresh spawn
    vim.wait(3000, function() return sent_to_job ~= nil end)
    vim.fn.chansend = real

    local inst = agent._get_instance("pi", 0)
    assert.is_table(inst, "default instance spawned")
    assert.equals(inst.job_id, sent_to_job)
  end)

  it("count send to a dead instance spawns it exactly once (no double-spawn)", function()
    agent.Toggle("pi", nil, "vsplit", 0)
    local open_calls = 0
    local real_open = agent.Open
    agent.Open = function(...)
      open_calls = open_calls + 1
      return real_open(...)
    end

    local sent_to_job
    local real = vim.fn.chansend
    vim.fn.chansend = function(job, _)
      sent_to_job = job
      return 1
    end
    agent._send_with_count("SendText", 2, "hi", false)
    vim.wait(3000, function() return sent_to_job ~= nil end)
    vim.fn.chansend = real
    agent.Open = real_open

    assert.equals(1, open_calls)
    local p2 = agent._get_instance("pi", 2)
    assert.is_table(p2)
    assert.equals(p2.job_id, sent_to_job)
  end)

  it("cancelling the window picker drops the send entirely", function()
    agent.Toggle("opencode", nil, "vsplit", 0)
    agent.Toggle("opencode", nil, "vsplit", 1)
    package.loaded["tw.agent.window_picker"] = {
      pick = function(_, cb) cb(nil) end,
    }
    local before_mode, before_index = agent.active_mode, agent.active_index
    local win_count = #vim.api.nvim_tabpage_list_wins(0)

    local sent_to_job = with_chansend_spy(function()
      agent._send_with_count("SendText", 0, "hello", false)
    end)

    assert.is_nil(sent_to_job)
    assert.equals(before_mode, agent.active_mode)
    assert.equals(before_index, agent.active_index)
    assert.equals(win_count, #vim.api.nvim_tabpage_list_wins(0))
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
