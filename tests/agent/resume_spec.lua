describe("resume", function()
  local resume

  before_each(function()
    package.loaded["tw.agent.resume"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    resume = require("tw.agent.resume")
  end)

  local function list_json(rows)
    return vim.json.encode(rows)
  end

  it("returns --continue for claude", function()
    local args = resume.args_for("claude", 0, "/wt", { list_sessions = function() return "[]" end })
    assert.same({ "--continue" }, args)
  end)

  it("returns empty args for codex and pi (fresh launch)", function()
    local opts = { list_sessions = function() return "[]" end }
    assert.same({}, resume.args_for("codex", 0, "/wt", opts))
    assert.same({}, resume.args_for("pi", 0, "/wt", opts))
  end)

  it("resolves opencode session by directory and recency", function()
    local rows = {
      { id = "ses_new", directory = "/wt", updated = 200 },
      { id = "ses_old", directory = "/wt", updated = 100 },
      { id = "ses_other", directory = "/elsewhere", updated = 999 },
    }
    local args = resume.args_for("opencode", 0, "/wt", {
      list_sessions = function() return list_json(rows) end,
    })
    assert.same({ "--session", "ses_new" }, args)
  end)

  it("falls back to --continue when no session matches the directory", function()
    local rows = { { id = "ses_other", directory = "/elsewhere", updated = 999 } }
    local args = resume.args_for("opencode", 0, "/wt", {
      list_sessions = function() return list_json(rows) end,
    })
    assert.same({ "--continue" }, args)
  end)

  it("falls back to --continue when session list command fails", function()
    local args = resume.args_for("opencode", 0, "/wt", {
      list_sessions = function() return nil end,
    })
    assert.same({ "--continue" }, args)
  end)

  it("does not throw when list_sessions errors", function()
    local args = resume.args_for("opencode", 0, "/wt", {
      list_sessions = function() error("boom") end,
    })
    assert.same({ "--continue" }, args)
  end)

  it("does not throw when updated fields are mixed types", function()
    local rows = {
      { id = "ses_str", directory = "/wt", updated = "100" },
      { id = "ses_num", directory = "/wt", updated = 200 },
    }
    local args = resume.args_for("opencode", 0, "/wt", {
      list_sessions = function() return list_json(rows) end,
    })
    assert.same({ "--session", "ses_num" }, args)
  end)

  it("captures the newest session created at/after launch, unclaimed", function()
    local rows = {
      { id = "ses_pre", directory = "/wt", created = 50, updated = 300 },
      { id = "ses_new", directory = "/wt", created = 200, updated = 210 },
      { id = "ses_older", directory = "/wt", created = 150, updated = 160 },
    }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.equals("ses_new", id)
  end)

  it("excludes sessions created before launch", function()
    local rows = { { id = "ses_pre", directory = "/wt", created = 50, updated = 999 } }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.is_nil(id)
  end)

  it("excludes already-claimed sessions", function()
    local rows = {
      { id = "ses_taken", directory = "/wt", created = 300, updated = 300 },
      { id = "ses_free", directory = "/wt", created = 200, updated = 200 },
    }
    local id = resume.capture_session_id("/wt", 100, { ses_taken = true }, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.equals("ses_free", id)
  end)

  it("breaks created ties deterministically by id descending", function()
    local rows = {
      { id = "ses_aaa", directory = "/wt", created = 200, updated = 200 },
      { id = "ses_zzz", directory = "/wt", created = 200, updated = 200 },
    }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.equals("ses_zzz", id)
  end)

  it("excludes sessions with missing or non-numeric created", function()
    local rows = { { id = "ses_nocreate", directory = "/wt", updated = 999 } }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.is_nil(id)
  end)

  it("returns nil and does not throw on decode failure", function()
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return "not json {{{" end,
    })
    assert.is_nil(id)
  end)

  it("returns nil and does not throw when list command errors", function()
    local id
    assert.has_no.errors(function()
      id = resume.capture_session_id("/wt", 100, {}, {
        list_sessions = function() error("boom") end,
      })
    end)
    assert.is_nil(id)
  end)

  it("includes a session created exactly at launch_ts", function()
    local rows = { { id = "ses_boundary", directory = "/wt", created = 100, updated = 100 } }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.equals("ses_boundary", id)
  end)

  it("returns nil when list output is nil or empty", function()
    assert.is_nil(resume.capture_session_id("/wt", 100, {}, { list_sessions = function() return nil end }))
    assert.is_nil(resume.capture_session_id("/wt", 100, {}, { list_sessions = function() return "" end }))
  end)

  it("excludes a session whose created is non-numeric", function()
    local rows = { { id = "ses_badcreated", directory = "/wt", created = "oops", updated = 999 } }
    local id = resume.capture_session_id("/wt", 100, {}, {
      list_sessions = function() return list_json(rows) end,
    })
    assert.is_nil(id)
  end)
end)
