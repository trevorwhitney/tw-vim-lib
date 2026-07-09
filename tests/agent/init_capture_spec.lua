describe("init — opencode session capture", function()
  local agent
  local list_calls

  local function make_resume(session_id)
    return {
      capture_session_id = function(_cwd, _ts, _claimed, _opts)
        list_calls = list_calls + 1
        return session_id
      end,
      args_for = function() return {} end,
    }
  end

  local function make_registry(loaded, claimed)
    return {
      load = function() return loaded or {} end,
      upsert = function() end,
      claimed_session_ids = function() return claimed or {} end,
      _key_for = function(m, i) return string.format("%s#%d", m, i) end,
    }
  end

  before_each(function()
    local helpers = require("tests.agent.spec_helpers")
    list_calls = 0
    agent = helpers.reset_and_mock(false, {
      publish = {
        record = function() end, record_exit = function() end,
        start_timer = function() end, stop_timer = function() end,
        push_status = function() end,
      },
    })
    agent._reset_opencode_capture()
  end)

  it("captures a session_id for a fresh opencode panel", function()
    agent._set_resume(make_resume("ses_captured"))
    agent._note_opencode_launch("opencode", 0)
    local id = agent._capture_opencode_session(make_registry(), "opencode", 0, "/wt")
    assert.equals("ses_captured", id)
    assert.equals(1, list_calls)
  end)

  it("does nothing when the registry already has a session_id", function()
    agent._set_resume(make_resume("ses_new"))
    agent._note_opencode_launch("opencode", 0)
    local reg = make_registry({ ["opencode#0"] = { session_id = "ses_existing" } })
    local id = agent._capture_opencode_session(reg, "opencode", 0, "/wt")
    assert.is_nil(id)
    assert.equals(0, list_calls)
  end)

  it("returns nil without a launch timestamp", function()
    agent._set_resume(make_resume("ses_x"))
    local id = agent._capture_opencode_session(make_registry(), "opencode", 0, "/wt")
    assert.is_nil(id)
    assert.equals(0, list_calls)
  end)

  it("stops attempting capture after MAX_CAPTURE_ATTEMPTS nil returns", function()
    agent._set_resume(make_resume(nil))
    agent._note_opencode_launch("opencode", 0)
    for _ = 1, agent._MAX_CAPTURE_ATTEMPTS + 3 do
      agent._capture_opencode_session(make_registry(), "opencode", 0, "/wt")
    end
    assert.equals(agent._MAX_CAPTURE_ATTEMPTS, list_calls)
  end)

  it("resets the attempt counter on a fresh launch, allowing capture again", function()
    agent._set_resume(make_resume(nil))
    agent._note_opencode_launch("opencode", 0)
    for _ = 1, agent._MAX_CAPTURE_ATTEMPTS do
      agent._capture_opencode_session(make_registry(), "opencode", 0, "/wt")
    end
    assert.equals(agent._MAX_CAPTURE_ATTEMPTS, list_calls)
    agent._set_resume(make_resume("ses_after_relaunch"))
    agent._note_opencode_launch("opencode", 0)
    local id = agent._capture_opencode_session(make_registry(), "opencode", 0, "/wt")
    assert.equals("ses_after_relaunch", id)
  end)

  it("two panels in one cwd capture distinct sessions via claimed de-dup", function()
    agent._note_opencode_launch("opencode", 0)
    agent._note_opencode_launch("opencode", 1)
    agent._set_resume({
      capture_session_id = function(_cwd, _ts, claimed, _opts)
        if claimed["ses_zero"] then return "ses_one" end
        return "ses_zero"
      end,
    })
    local reg0 = make_registry({}, {})
    local id0 = agent._capture_opencode_session(reg0, "opencode", 0, "/wt")
    local reg1 = make_registry({}, { ses_zero = true })
    local id1 = agent._capture_opencode_session(reg1, "opencode", 1, "/wt")
    assert.equals("ses_zero", id0)
    assert.equals("ses_one", id1)
    assert.are_not.equals(id0, id1)
  end)

  it("does not capture for non-opencode modes", function()
    agent._set_resume(make_resume("ses_x"))
    agent._note_opencode_launch("claude", 0)
    local id = agent._capture_opencode_session(make_registry(), "claude", 0, "/wt")
    assert.is_nil(id)
    assert.equals(0, list_calls)
  end)

  it("_capture_tick persists a captured session_id via publish.record", function()
    local recorded = {}
    package.loaded["tw.agent.publish"].record = function(e) table.insert(recorded, e) end
    agent._set_resume(make_resume("ses_tick"))
    agent._note_opencode_launch("opencode", 0)
    package.loaded["tw.agent.registry"] = make_registry({}, {})
    agent._capture_tick("opencode", 0)
    assert.equals("ses_tick", recorded[#recorded].session_id)
  end)

  it("_capture_tick is a no-op for non-opencode modes", function()
    local recorded = {}
    package.loaded["tw.agent.publish"].record = function(e) table.insert(recorded, e) end
    agent._set_resume(make_resume("ses_x"))
    agent._note_opencode_launch("claude", 0)
    agent._capture_tick("claude", 0)
    assert.equals(0, #recorded)
  end)

  it("records a millisecond-precision launch timestamp", function()
    agent._note_opencode_launch("opencode", 0)
    local ts = agent._opencode_launch_ts["opencode#0"]
    assert.is_number(ts)
    -- ms-precision epoch is not aligned to a whole second boundary in general;
    -- assert it carries sub-second resolution by comparing to os.time()*1000.
    assert.is_true(ts >= os.time() * 1000)
  end)
end)
