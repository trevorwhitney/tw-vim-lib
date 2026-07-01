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
end)
