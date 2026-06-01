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
