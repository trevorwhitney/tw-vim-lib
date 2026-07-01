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
