describe("publish — registry sink", function()
  local publish
  local writes

  before_each(function()
    package.loaded["tw.agent.publish"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    writes = {}
    package.loaded["tw.agent.registry"] = {
      upsert = function(root, mode, idx, fields)
        table.insert(writes, { root = root, mode = mode, idx = idx, fields = fields })
      end,
      load = function() return {} end,
    }
    publish = require("tw.agent.publish")
  end)

  it("maps working/waiting to workmux status names", function()
    assert.equals("working", publish._workmux_status("working"))
    assert.equals("waiting", publish._workmux_status("waiting"))
    assert.is_nil(publish._workmux_status("dead"))
    assert.is_nil(publish._workmux_status("restorable"))
  end)

  it("writes a registry record on record()", function()
    publish.record({ root = "/wt", mode = "opencode", idx = 0, cwd = "/wt",
      status = "working", description = "task" })
    assert.equals(1, #writes)
    assert.equals("opencode", writes[1].mode)
    assert.equals("working", writes[1].fields.last_status)
    assert.equals("task", writes[1].fields.description)
    assert.is_number(writes[1].fields.updated_ts)
  end)

  it("records last_status='restorable' on exit", function()
    publish.record_exit({ root = "/wt", mode = "claude", idx = 1, cwd = "/wt" })
    assert.equals("restorable", writes[1].fields.last_status)
  end)

  it("forwards session_id when present", function()
    publish.record({ root = "/wt", mode = "opencode", idx = 0, cwd = "/wt",
      status = "working", session_id = "ses_x" })
    assert.equals("ses_x", writes[1].fields.session_id)
  end)

  it("omits session_id when absent", function()
    publish.record({ root = "/wt", mode = "opencode", idx = 0, cwd = "/wt",
      status = "working" })
    assert.is_nil(writes[1].fields.session_id)
  end)
end)

describe("publish — workmux sink", function()
  local publish
  local calls

  before_each(function()
    package.loaded["tw.agent.publish"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    package.loaded["tw.agent.registry"] = {
      upsert = function() end, load = function() return {} end,
    }
    publish = require("tw.agent.publish")
    calls = {}
    publish._set_workmux_runner(function(status) table.insert(calls, status) end)
    publish._reset_pushed()
  end)

  it("pushes working then waiting on transition", function()
    publish.push_status("opencode", 0, "working")
    publish.push_status("opencode", 0, "waiting")
    assert.same({ "working", "waiting" }, calls)
  end)

  it("suppresses repeated identical status", function()
    publish.push_status("opencode", 0, "working")
    publish.push_status("opencode", 0, "working")
    assert.same({ "working" }, calls)
  end)

  it("does not call workmux for dead status", function()
    publish.push_status("opencode", 0, "working")
    publish.push_status("opencode", 0, "dead")
    assert.same({ "working" }, calls)
  end)

  it("tracks transitions per slot independently", function()
    publish.push_status("opencode", 0, "working")
    publish.push_status("claude", 1, "working")
    assert.same({ "working", "working" }, calls)
  end)
end)

describe("publish — failure isolation", function()
  local publish

  before_each(function()
    package.loaded["tw.agent.publish"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    package.loaded["tw.agent.registry"] = {
      upsert = function() error("boom") end,
      load = function() return {} end,
    }
    publish = require("tw.agent.publish")
  end)

  it("does not throw when registry.upsert errors on record", function()
    assert.has_no.errors(function()
      publish.record({ root = "/wt", mode = "opencode", idx = 0, cwd = "/wt", status = "working" })
    end)
  end)

  it("does not throw when registry.upsert errors on record_exit", function()
    assert.has_no.errors(function()
      publish.record_exit({ root = "/wt", mode = "claude", idx = 0, cwd = "/wt" })
    end)
  end)
end)

describe("publish — timer lifecycle", function()
  local publish
  local created

  before_each(function()
    package.loaded["tw.agent.publish"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    package.loaded["tw.agent.registry"] = {
      upsert = function() end, load = function() return {} end,
    }
    publish = require("tw.agent.publish")
    created = 0
    local fake = { start = function() end, stop = function() end, close = function() end }
    publish._set_timer_factory(function()
      created = created + 1
      return fake
    end)
  end)

  it("creates only one timer across repeated start_timer calls", function()
    publish.start_timer(function() return {} end, 1000)
    publish.start_timer(function() return {} end, 1000)
    assert.equals(1, created)
    publish.stop_timer()
  end)

   it("stop_timer is safe when no timer is running", function()
      assert.has_no.errors(function()
        publish.stop_timer()
      end)
    end)

  it("invokes the capture hook for each ticked instance", function()
    local hook_calls = {}
    local status_detect_calls = 0
    publish._set_capture_hook(function(mode, idx) table.insert(hook_calls, mode .. "#" .. idx) end)
    package.loaded["tw.agent.status"] = {
      detect = function()
        status_detect_calls = status_detect_calls + 1
        return "working"
      end,
    }
    local unwrapped_cb
    local fake2 = {
      start = function(_, _, _, fn)
        unwrapped_cb = fn
      end,
      stop = function() end,
      close = function() end
    }
    publish._set_timer_factory(function() return fake2 end)
    publish.start_timer(function() return { { mode = "opencode", idx = 0 } } end, 1000)
    assert.is_function(unwrapped_cb)
    unwrapped_cb()
    vim.wait(10)
    assert.equals(1, status_detect_calls)
    assert.same({ "opencode#0" }, hook_calls)
    publish.stop_timer()
    publish._set_capture_hook(nil)
  end)
end)

describe("init publisher wiring", function()
  local agent
  local recorded

  before_each(function()
    local helpers = require("tests.agent.spec_helpers")
    recorded = { record = {}, exit = {} }
    agent = helpers.reset_and_mock(false, {
      publish = {
        record = function(e) table.insert(recorded.record, e) end,
        record_exit = function(e) table.insert(recorded.exit, e) end,
        start_timer = function() end,
        stop_timer = function() end,
        push_status = function() end,
      },
    })
  end)

  it("records a session when set_instance runs", function()
    agent._set_instance("opencode", 0, 10, 999)
    assert.equals(1, #recorded.record)
    assert.equals("opencode", recorded.record[1].mode)
    assert.equals(0, recorded.record[1].idx)
  end)

  it("stores mode on the instance for the timer's status.detect path", function()
    agent._set_instance("claude", 2, 11, 998)
    local inst = agent._get_instance("claude", 2)
    assert.equals("claude", inst.mode)
  end)
end)

describe("publish — session_id survives exit", function()
  local publish
  local tmpdir

  before_each(function()
    package.loaded["tw.agent.publish"] = nil
    package.loaded["tw.agent.registry"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    require("tw.agent.registry")
    publish = require("tw.agent.publish")
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    package.loaded["tw.agent.registry"] = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("keeps a recorded session_id after record_exit", function()
    publish.record({ root = tmpdir, mode = "opencode", idx = 0, cwd = tmpdir,
      status = "working", session_id = "ses_keep" })
    publish.record_exit({ root = tmpdir, mode = "opencode", idx = 0, cwd = tmpdir })
    local registry = require("tw.agent.registry")
    local entries = registry.load(tmpdir)
    assert.equals("ses_keep", entries["opencode#0"].session_id)
    assert.equals("restorable", entries["opencode#0"].last_status)
  end)
end)
