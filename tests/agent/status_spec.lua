local helpers = require("tests.agent.spec_helpers")

describe("status.detect — OpenCode pattern scraping", function()
  local status

  before_each(function()
    package.loaded["tw.agent.status"] = nil
    status = require("tw.agent.status")
    status.reset()
  end)

  local function make_instance(buf, opts)
    opts = opts or {}
    return {
      mode = opts.mode or "opencode",
      idx = opts.idx or 0,
      buf = buf,
      job_id = opts.job_id or 9999, -- non-nil, will pass jobwait stub
    }
  end

  it("returns 'working' when 'Thinking...' is present", function()
    local buf = helpers.mock_terminal_buffer({ "some preamble", "Thinking..." })
    local inst = make_instance(buf)
    -- Stub jobwait to return -1 (alive)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(inst))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'working' for 'Generating...'", function()
    local buf = helpers.mock_terminal_buffer({ "Generating..." })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'waiting' when 'press enter to send the message' is present", function()
    local buf = helpers.mock_terminal_buffer({
      "Some prior output",
      "press enter to send the message",
    })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("waiting", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips ANSI escape sequences before matching", function()
    local ansi_line = "\27[31m\27[1mThinking...\27[0m"
    local buf = helpers.mock_terminal_buffer({ ansi_line })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns last known status when no pattern matches", function()
    -- First call: working
    local buf = helpers.mock_terminal_buffer({ "Thinking..." })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf)))

    -- Replace with ambiguous content (no patterns), invalidate cache so it
    -- actually re-runs detection
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "ambiguous garbage" })
    status.invalidate(buf)
    -- Should keep last known: working
    assert.equals("working", status.detect(make_instance(buf)))

    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("caches within 500ms window", function()
    local buf = helpers.mock_terminal_buffer({ "Thinking..." })
    local orig = vim.fn.jobwait
    local jobwait_calls = 0
    vim.fn.jobwait = function() jobwait_calls = jobwait_calls + 1; return { -1 } end

    assert.equals("working", status.detect(make_instance(buf)))
    local first_calls = jobwait_calls
    -- Immediate second call should be cached
    assert.equals("working", status.detect(make_instance(buf)))
    assert.equals(first_calls, jobwait_calls, "jobwait should not be called again within cache window")

    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips OSC sequences terminated by ESC backslash (ST)", function()
    -- OSC 0 (set window title) with ST terminator: ESC ] 0 ; title ESC \
    local line = "\27]0;some title\27\\Thinking..."
    local buf = helpers.mock_terminal_buffer({ line })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips CSI sequences with private modifiers (e.g. cursor hide)", function()
    -- ESC [ ? 2 5 l = hide cursor; should be stripped before pattern match
    local line = "\27[?25lThinking..."
    local buf = helpers.mock_terminal_buffer({ line })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("BufWipeout autocmd clears cache for the wiped buffer", function()
    local buf = helpers.mock_terminal_buffer({ "Thinking..." })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    status.detect(make_instance(buf))
    -- Confirm something was cached (we re-detect; if it was cached, jobwait won't be called again)
    -- But more directly: wipe and verify subsequent detect of a NEW buffer reuses the same buf number
    -- without inheriting old status.
    vim.api.nvim_buf_delete(buf, { force = true })

    -- Now create a new buffer; Neovim may reuse the same buffer number.
    -- If the BufWipeout autocmd worked, last_known[buf] is nil.
    local buf2 = helpers.mock_terminal_buffer({ "ambiguous garbage" })
    status.invalidate(buf2) -- ensure no cache hit
    local result = status.detect(make_instance(buf2))
    -- With ambiguous content and no last_known entry, default is "waiting"
    assert.equals("waiting", result)
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf2, { force = true })
  end)

  it("prioritizes waiting over working when both patterns appear", function()
    -- Simulates a buffer where 'Thinking...' is leftover from a prior turn
    -- and 'press enter to send the message' is the current idle prompt.
    local buf = helpers.mock_terminal_buffer({
      "(earlier output)",
      "Thinking...",
      "(more output)",
      "press enter to send the message",
    })
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("waiting", status.detect(make_instance(buf)))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("status.detect — timing heuristic for non-opencode modes", function()
  local status

  before_each(function()
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.agent.buffer-config"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    status = require("tw.agent.status")
    status.reset()
  end)

  local function make_instance(buf, mode)
    return {
      mode = mode or "claude",
      idx = 0,
      buf = buf,
      job_id = 9999,
    }
  end

  it("returns 'working' when last_change_at is within 30s", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})
    buffer_config.buffer_states[buf].last_change_at = vim.uv.now() - 5000

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("working", status.detect(make_instance(buf, "claude")))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'waiting' when last_change_at is older than 30s", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})
    buffer_config.buffer_states[buf].last_change_at = vim.uv.now() - 31000

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("waiting", status.detect(make_instance(buf, "claude")))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'waiting' when last_change_at is nil", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    assert.equals("waiting", status.detect(make_instance(buf, "pi")))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'dead' when job_id is nil regardless of last_change_at", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})
    buffer_config.buffer_states[buf].last_change_at = vim.uv.now()
    assert.equals("dead", status.detect({
      mode = "claude", idx = 0, buf = buf, job_id = nil,
    }))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 'dead' when jobwait returns non-negative-one", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})
    buffer_config.buffer_states[buf].last_change_at = vim.uv.now()
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { 0 } end -- exited cleanly
    assert.equals("dead", status.detect(make_instance(buf, "codex")))
    vim.fn.jobwait = orig
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("falls back to 'waiting' when buffer-config cannot be loaded", function()
    -- Force require to fail for tw.agent.buffer-config by replacing its
    -- package.preload entry with a function that errors. The pcall inside
    -- detect_timing will catch this and fall through to the safe default.
    package.loaded["tw.agent.buffer-config"] = nil
    package.preload["tw.agent.buffer-config"] = function()
      error("simulated require failure")
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    -- With no last_known entry and require failing, the result must be "waiting".
    assert.equals("waiting", status.detect(make_instance(buf, "claude")))

    vim.fn.jobwait = orig
    package.preload["tw.agent.buffer-config"] = nil
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("treats last_change_at exactly 30000ms ago as 'waiting' (boundary)", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local buffer_config = require("tw.agent.buffer-config")
    buffer_config.setup_buffer(buf, {})

    -- Pin "now" via stubbing vim.uv.now so the delta is exactly WORKING_STALE_MS.
    local now = vim.uv.now()
    local orig_now = vim.uv.now
    vim.uv.now = function() return now end
    buffer_config.buffer_states[buf].last_change_at = now - 30000

    local orig_jobwait = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    -- detect's own jobwait-cached timestamp also uses vim.uv.now(), so the
    -- stub stays consistent throughout the call.
    assert.equals("waiting", status.detect(make_instance(buf, "claude")))

    vim.fn.jobwait = orig_jobwait
    vim.uv.now = orig_now
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
