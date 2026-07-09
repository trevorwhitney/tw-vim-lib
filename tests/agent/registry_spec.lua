describe("registry", function()
  local registry
  local tmpdir

  before_each(function()
    package.loaded["tw.agent.registry"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    registry = require("tw.agent.registry")
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    vim.fn.delete(tmpdir, "rf")
  end)

  local function now() return os.time() end

  it("roundtrips an upserted entry", function()
    registry.upsert(tmpdir, "opencode", 0, {
      cwd = tmpdir, last_status = "working",
      description = "task", updated_ts = now(),
    })
    local entries = registry.load(tmpdir)
    assert.equals("opencode", entries["opencode#0"].mode)
    assert.equals(0, entries["opencode#0"].idx)
    assert.equals("working", entries["opencode#0"].last_status)
  end)

  it("coerces idx from the string key to a number on load", function()
    registry.upsert(tmpdir, "opencode", 3, { cwd = tmpdir, updated_ts = now() })
    local entries = registry.load(tmpdir)
    assert.equals(3, entries["opencode#3"].idx)
    assert.equals("number", type(entries["opencode#3"].idx))
  end)

  it("leaves no .tmp file after write", function()
    registry.upsert(tmpdir, "claude", 0, { cwd = tmpdir, updated_ts = now() })
    local leftovers = vim.fn.glob(tmpdir .. "/.workmux/*.tmp", false, true)
    assert.equals(0, #leftovers)
  end)

  it("treats corrupt JSON as empty", function()
    vim.fn.mkdir(tmpdir .. "/.workmux", "p")
    local f = io.open(tmpdir .. "/.workmux/agent-sessions.json", "w")
    f:write("not json {{{"); f:close()
    assert.same({}, registry.load(tmpdir))
  end)

  it("prunes entries older than 14 days on load", function()
    local old_ts = now() - (15 * 24 * 60 * 60)
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, updated_ts = old_ts })
    registry.upsert(tmpdir, "opencode", 1, { cwd = tmpdir, updated_ts = now() })
    local entries = registry.load(tmpdir)
    assert.is_nil(entries["opencode#0"])
    assert.is_not_nil(entries["opencode#1"])
  end)

  it("returns empty when no file exists", function()
    assert.same({}, registry.load(tmpdir))
  end)

  it("does not throw when a stored updated_ts is not a number", function()
    vim.fn.mkdir(tmpdir .. "/.workmux", "p")
    local f = io.open(tmpdir .. "/.workmux/agent-sessions.json", "w")
    f:write(vim.json.encode({
      version = 1,
      sessions = { ["opencode#0"] = { cwd = tmpdir, updated_ts = "oops" } },
    }))
    f:close()
    local entries = registry.load(tmpdir)
    assert.is_nil(entries["opencode#0"])
  end)

  it("derives numeric idx from the session key", function()
    vim.fn.mkdir(tmpdir .. "/.workmux", "p")
    local f = io.open(tmpdir .. "/.workmux/agent-sessions.json", "w")
    f:write(vim.json.encode({
      version = 1,
      sessions = { ["opencode#2"] = { mode = "opencode", cwd = tmpdir, updated_ts = now() } },
    }))
    f:close()
    local entries = registry.load(tmpdir)
    assert.equals(2, entries["opencode#2"].idx)
    assert.equals("number", type(entries["opencode#2"].idx))
  end)

  it("removes an entry via delete", function()
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, updated_ts = now() })
    registry.upsert(tmpdir, "opencode", 1, { cwd = tmpdir, updated_ts = now() })
    registry.delete(tmpdir, "opencode", 0)
    local entries = registry.load(tmpdir)
    assert.is_nil(entries["opencode#0"])
    assert.is_not_nil(entries["opencode#1"])
  end)

  it("delete is a no-op when the entry does not exist", function()
    registry.upsert(tmpdir, "opencode", 1, { cwd = tmpdir, updated_ts = now() })
    assert.has_no.errors(function()
      registry.delete(tmpdir, "opencode", 5)
    end)
    local entries = registry.load(tmpdir)
    assert.is_not_nil(entries["opencode#1"])
  end)

  it("delete leaves no .tmp file behind", function()
    registry.upsert(tmpdir, "claude", 0, { cwd = tmpdir, updated_ts = now() })
    registry.delete(tmpdir, "claude", 0)
    local leftovers = vim.fn.glob(tmpdir .. "/.workmux/*.tmp", false, true)
    assert.equals(0, #leftovers)
  end)

  it("merges fields on upsert, preserving omitted ones", function()
    registry.upsert(tmpdir, "opencode", 0, {
      cwd = tmpdir, last_status = "working",
      session_id = "ses_keep", updated_ts = now(),
    })
    registry.upsert(tmpdir, "opencode", 0, {
      cwd = tmpdir, last_status = "restorable", updated_ts = now(),
    })
    local entries = registry.load(tmpdir)
    assert.equals("ses_keep", entries["opencode#0"].session_id)
    assert.equals("restorable", entries["opencode#0"].last_status)
  end)

  it("still overwrites fields that are provided", function()
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, last_status = "working", updated_ts = now() })
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, last_status = "waiting", updated_ts = now() })
    local entries = registry.load(tmpdir)
    assert.equals("waiting", entries["opencode#0"].last_status)
  end)

  it("collects claimed session_ids excluding the given key", function()
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, session_id = "ses_a", updated_ts = now() })
    registry.upsert(tmpdir, "opencode", 1, { cwd = tmpdir, session_id = "ses_b", updated_ts = now() })
    local claimed = registry.claimed_session_ids(tmpdir, registry._key_for("opencode", 1))
    assert.is_true(claimed["ses_a"])
    assert.is_nil(claimed["ses_b"])
  end)

  it("returns an empty set when no session_ids are stored", function()
    registry.upsert(tmpdir, "opencode", 0, { cwd = tmpdir, updated_ts = now() })
    assert.same({}, registry.claimed_session_ids(tmpdir, "opencode#9"))
  end)

  it("skips entries whose session_id is not a string", function()
    vim.fn.mkdir(tmpdir .. "/.workmux", "p")
    local f = io.open(tmpdir .. "/.workmux/agent-sessions.json", "w")
    f:write(vim.json.encode({
      version = 1,
      sessions = {
        ["opencode#0"] = { mode = "opencode", session_id = 42, updated_ts = now() },
        ["opencode#1"] = { mode = "opencode", session_id = "ses_ok", updated_ts = now() },
      },
    }))
    f:close()
    local claimed = registry.claimed_session_ids(tmpdir, "opencode#9")
    assert.is_true(claimed["ses_ok"])
    assert.is_nil(claimed[42])
  end)
end)
