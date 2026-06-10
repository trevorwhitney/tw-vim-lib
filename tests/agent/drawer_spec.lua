local helpers = require("tests.agent.spec_helpers")

-- The drawer orchestrates two windows as a single left "drawer":
--   1. the file tree (nvim-tree), pinned top-left
--   2. the agent sidebar, stacked directly below it
-- nvim-tree is not available under headless test runs, so the drawer accepts
-- an injectable tree backend (open/close/is_open) that these tests stub.

describe("drawer", function()
  local drawer, sidebar

  -- A fake nvim-tree backend: open() spawns a real left split with the
  -- NvimTree filetype (so the sidebar's stacking logic detects it), close()
  -- tears it down, and is_open() reports state. Calls are recorded in order.
  local function make_fake_tree()
    local tree = { win = nil, calls = {} }
    function tree.is_open()
      return tree.win ~= nil and vim.api.nvim_win_is_valid(tree.win)
    end
    function tree.open()
      table.insert(tree.calls, "open")
      if tree.is_open() then
        return
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].filetype = "NvimTree"
      tree.win = vim.api.nvim_open_win(buf, false, { split = "left", win = -1, width = 30 })
    end
    function tree.close()
      table.insert(tree.calls, "close")
      if tree.is_open() then
        pcall(vim.api.nvim_win_close, tree.win, true)
      end
      tree.win = nil
    end
    return tree
  end

  before_each(function()
    package.loaded["tw.agent.drawer"] = nil
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.log"] = {
      info = function() end,
      warn = function() end,
      error = function() end,
      debug = function() end,
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

  it("open() opens the tree before the agent sidebar", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })

    drawer.open()

    -- Tree opened first so the sidebar's stacking path can detect it.
    assert.equals("open", tree.calls[1])
    assert.is_true(tree.is_open())
    assert.is_true(vim.api.nvim_win_is_valid(sidebar._state().win))

    -- Stacked: same left column, sidebar below the tree.
    local nt_pos = vim.api.nvim_win_get_position(tree.win)
    local ag_pos = vim.api.nvim_win_get_position(sidebar._state().win)
    assert.equals(nt_pos[2], ag_pos[2])
    assert.is_true(ag_pos[1] > nt_pos[1], "sidebar should be below the tree")
  end)

  it("open() stacks the sidebar even with no active agent sessions", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })

    drawer.open()

    -- Both present regardless of session count: sidebar renders empty-state.
    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.equals("(no active sessions)", lines[3])
    assert.equals(sidebar._stacked_height(), vim.api.nvim_win_get_height(sidebar._state().win))
  end)

  it("close() closes both the sidebar and the tree", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })

    drawer.open()
    drawer.close()

    assert.is_nil(sidebar._state().win)
    assert.is_false(tree.is_open())
  end)

  it("toggle() opens when closed and closes when open", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })

    drawer.toggle()
    assert.is_true(tree.is_open())
    assert.is_true(vim.api.nvim_win_is_valid(sidebar._state().win))

    drawer.toggle()
    assert.is_false(tree.is_open())
    assert.is_nil(sidebar._state().win)
  end)

  it("toggle() treats either window being open as 'open' (closes both)", function()
    local tree = make_fake_tree()
    drawer.setup({ tree = tree })

    -- Only the sidebar is open (tree closed): toggle must close, not re-open.
    sidebar.open()
    assert.is_false(tree.is_open())

    drawer.toggle()
    assert.is_nil(sidebar._state().win)
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
