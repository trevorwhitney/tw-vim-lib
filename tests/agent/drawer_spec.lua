local helpers = require("tests.agent.spec_helpers")

describe("drawer", function()
  local drawer, sidebar

  local function make_fake_tree()
    local tree = { open_calls = 0, close_calls = 0, opened = false }
    function tree.is_open()
      return tree.opened
    end
    function tree.open()
      tree.open_calls = tree.open_calls + 1
      tree.opened = true
    end
    function tree.close()
      tree.close_calls = tree.close_calls + 1
      tree.opened = false
    end
    return tree
  end

  before_each(function()
    package.loaded["tw.agent.drawer"] = nil
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
    drawer = require("tw.agent.drawer")
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("open() opens the tree and the sidebar", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })
    drawer.open()
    assert.equals(1, tree.open_calls)
    assert.is_true(sidebar.is_open())
  end)

  it("close() closes both the sidebar and the tree", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })
    drawer.open()
    drawer.close()
    assert.is_false(sidebar.is_open())
    assert.is_false(tree.is_open())
  end)

  it("toggle() opens when closed and closes when open", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })
    drawer.toggle()
    assert.is_true(tree.is_open())
    assert.is_true(sidebar.is_open())
    drawer.toggle()
    assert.is_false(tree.is_open())
    assert.is_false(sidebar.is_open())
  end)

  it("toggle() treats either half open as 'open' (closes both)", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })
    sidebar.open()
    assert.is_false(tree.is_open())
    drawer.toggle()
    assert.is_false(sidebar.is_open())
    assert.is_false(tree.is_open())
  end)

  it("open() is idempotent: a second call does not create a second sidebar", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })
    drawer.open()
    drawer.open()
    local buf = sidebar._state().buf
    local count = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == buf then
        count = count + 1
      end
    end
    assert.equals(1, count)
  end)
end)
