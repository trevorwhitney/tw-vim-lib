local helpers = require("tests.agent.spec_helpers")

describe("sidebar lifecycle", function()
  local sidebar

  before_each(function()
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    helpers.reset_and_mock(false)
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({})
    pcall(sidebar.close)
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("open() creates a window and buffer", function()
    sidebar.open()
    local state = sidebar._state()
    assert.is_true(vim.api.nvim_win_is_valid(state.win))
    assert.is_true(vim.api.nvim_buf_is_valid(state.buf))
  end)

  it("close() is idempotent", function()
    sidebar.open()
    sidebar.close()
    sidebar.close() -- second call must not error
    local state = sidebar._state()
    assert.is_nil(state.win)
    assert.is_nil(state.buf)
  end)

  it("toggle() opens when closed, closes when open", function()
    sidebar.toggle()
    assert.is_true(vim.api.nvim_win_is_valid(sidebar._state().win))
    sidebar.toggle()
    assert.is_nil(sidebar._state().win)
  end)

  it("setup({ enabled = false }) prevents open from creating a window", function()
    sidebar.close()
    package.loaded["tw.agent.sidebar"] = nil
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = false })
    sidebar.open()
    assert.is_nil(sidebar._state().win)
  end)

   it("sidebar buffer has buftype=nofile and is unmodifiable by default", function()
     sidebar.open()
     local buf = sidebar._state().buf
     assert.equals("nofile", vim.bo[buf].buftype)
     assert.is_false(vim.bo[buf].modifiable)
   end)

   it("handles external window close gracefully", function()
      sidebar.open()
      local win = sidebar._state().win
      assert.is_true(vim.api.nvim_win_is_valid(win))

      -- Simulate the user running :q on the sidebar window
      vim.api.nvim_win_close(win, true)

      -- close() must not raise and must reset state
      sidebar.close()
      local state = sidebar._state()
      assert.is_nil(state.win)
      assert.is_nil(state.buf)

      -- A subsequent open() must recreate a valid window/buffer
      sidebar.open()
      assert.is_true(vim.api.nvim_win_is_valid(sidebar._state().win))
      assert.is_true(vim.api.nvim_buf_is_valid(sidebar._state().buf))
    end)
end)

describe("sidebar rendering", function()
  local sidebar
  local agent

  before_each(function()
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    agent = helpers.reset_and_mock(false)
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({})
    pcall(sidebar.close)
  end)

  after_each(function() pcall(sidebar.close) end)

  local function setup_alive_instance(mode, idx)
    local buf = vim.api.nvim_create_buf(false, true)
    local job_id = 9000 + idx
    agent._set_instance(mode, idx, buf, job_id)
    return buf, job_id
  end

  it("refresh() renders empty-state when no instances are alive", function()
    sidebar.open()
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { 0 } end
    sidebar.refresh()
    vim.fn.jobwait = orig
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.equals("⌬ Agents", lines[1])
    assert.equals("(no active sessions)", lines[3])
  end)

  it("refresh() renders one row per alive instance", function()
    local buf1, job1 = setup_alive_instance("opencode", 0)
    local buf2, job2 = setup_alive_instance("claude", 0)
    vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "press enter to send the message" })

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function(jobs)
      local id = jobs[1]
      if id == job1 then return { -1 } end
      if id == job2 then return { -1 } end
      return { 0 }
    end

    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(#lines >= 4)
    assert.is_true(lines[3]:find("oc#0") ~= nil)
    assert.is_true(lines[3]:find("waiting") ~= nil)
    assert.is_true(lines[4]:find("cl#0") ~= nil)
    assert.is_true(lines[4]:find("waiting") ~= nil)
  end)

  it("show_dead=false hides dead instances", function()
    setup_alive_instance("opencode", 0)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { 0 } end -- all dead
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    for _, l in ipairs(lines) do
      assert.is_nil(l:find("oc#0"))
    end
  end)

  it("show_dead=true keeps dead instances visible", function()
    package.loaded["tw.agent.sidebar"] = nil
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ show_dead = true })

    setup_alive_instance("opencode", 0)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { 0 } end -- exited
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    local found = false
    for _, l in ipairs(lines) do
      if l:find("oc#0") and l:find("dead") then found = true end
    end
    assert.is_true(found, "oc#0 dead row should be present when show_dead=true")
  end)

  it("docker modes are excluded from sidebar list", function()
    setup_alive_instance("opencode-docker", 0)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    for _, l in ipairs(lines) do
      assert.is_nil(l:find("docker"))
    end
  end)

  it("active session row is recorded in entries", function()
    setup_alive_instance("opencode", 0)
    agent.active_mode = "opencode"
    agent.active_index = 0
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig
    local entries = sidebar._state().entries
    assert.is_true(#entries >= 1)
    assert.is_true(entries[1].is_active)
  end)

  it("line_to_entry maps data-row line numbers to entry indices", function()
    setup_alive_instance("opencode", 0)
    setup_alive_instance("claude", 0)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig
    local map = sidebar._state().line_to_entry
    assert.equals(1, map[3])
    assert.equals(2, map[4])
    assert.is_nil(map[1])
    assert.is_nil(map[2])
  end)
end)
