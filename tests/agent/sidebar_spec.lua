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
    -- No interrupt hint -> opencode instance needs attention. The claude
    -- instance has no recent change either, so it also needs attention.
    vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "all done, which one?" })

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

  it("active highlight covers exactly the entry's two rows", function()
    setup_alive_instance("opencode", 0)
    setup_alive_instance("claude", 0)
    agent.active_mode = "opencode"
    agent.active_index = 0
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig

    local state = sidebar._state()
    local header_row = state.data_start_line - 1
    local marks = vim.api.nvim_buf_get_extmarks(
      state.buf,
      state.ns,
      { header_row, 0 },
      { header_row, -1 },
      { details = true }
    )

    local active_mark
    for _, mark in ipairs(marks) do
      if mark[4] and mark[4].line_hl_group == "TwAgentSidebarActive" then
        active_mark = mark
      end
    end

    assert.is_not_nil(active_mark, "active line highlight extmark should exist")
    -- Range is end-inclusive: header + description = end_row == header_row + 1.
    -- It must NOT extend to the next entry's header (header_row + 2).
    assert.equals(header_row, active_mark[2])
    assert.equals(header_row + 1, active_mark[4].end_row)
  end)

  it("cursor highlight covers both rows of the entry under the cursor", function()
    setup_alive_instance("opencode", 0)
    setup_alive_instance("claude", 0)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()

    local state = sidebar._state()
    -- Focus the sidebar and place the cursor on the first entry's header.
    vim.api.nvim_set_current_win(state.win)
    vim.api.nvim_win_set_cursor(state.win, { state.data_start_line, 0 })
    sidebar._apply_cursor_highlight()
    vim.fn.jobwait = orig

    -- The window must not use the built-in single-line cursorline.
    assert.is_false(vim.wo[state.win].cursorline)

    local header_row = state.data_start_line - 1
    local marks = vim.api.nvim_buf_get_extmarks(
      state.buf,
      state.cursor_ns,
      { header_row, 0 },
      { header_row, -1 },
      { details = true }
    )

    local cursor_mark
    for _, mark in ipairs(marks) do
      if mark[4] and mark[4].line_hl_group == "TwAgentSidebarCursor" then
        cursor_mark = mark
      end
    end

    assert.is_not_nil(cursor_mark, "cursor line highlight extmark should exist")
    assert.equals(header_row, cursor_mark[2])
    assert.equals(header_row + 1, cursor_mark[4].end_row)
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

  it("collect_entries includes description field", function()
    local buf = setup_alive_instance("opencode", 0)

    -- Mock description module
    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "fixing tests"
        end
        return nil
      end,
      generate = function() end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig
    package.loaded["tw.agent.description"] = nil

    local entries = sidebar._state().entries
    assert.is_true(#entries >= 1)
    assert.equals("fixing tests", entries[1].description)
  end)

  it("render_lines includes description in output", function()
    local buf = setup_alive_instance("opencode", 0)

    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "fixing tests"
        end
        return nil
      end,
      generate = function() end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig
    package.loaded["tw.agent.description"] = nil

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(#lines >= 3)
    assert.is_true(lines[3]:find("fixing tests") ~= nil)
  end)

  it("render_lines shows loading state", function()
    local buf = setup_alive_instance("opencode", 0)

    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "loading"
        end
        return nil
      end,
      generate = function() end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig
    package.loaded["tw.agent.description"] = nil

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("loading") ~= nil)
  end)

  it("render_lines shows error state", function()
    local buf = setup_alive_instance("opencode", 0)

    package.loaded["tw.agent.description"] = {
      get = function(b)
        if b == buf then
          return "error"
        end
        return nil
      end,
      generate = function() end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig
    package.loaded["tw.agent.description"] = nil

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("failed") ~= nil)
  end)
end)

describe("sidebar interaction", function()
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

  it("open() starts a refresh timer", function()
    sidebar.open()
    assert.is_not_nil(sidebar._state().timer)
  end)

  it("close() stops and clears the timer", function()
    sidebar.open()
    sidebar.close()
    assert.is_nil(sidebar._state().timer)
  end)

  it("<CR> on a data row calls agent.Open with the entry's mode and idx", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 9001)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    local captured = {}
    local orig_open = agent.Open
    agent.Open = function(mode, args, window_type, idx)
      captured = { mode = mode, args = args, window_type = window_type, idx = idx }
    end

    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    sidebar._activate_under_cursor()

    agent.Open = orig_open
    vim.fn.jobwait = orig

    assert.equals("opencode", captured.mode)
    assert.equals("vsplit", captured.window_type)
    assert.equals(0, captured.idx)
  end)

  it("<CR> on a non-data row is a no-op", function()
    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { 1, 0 })
    local called = false
    local orig_open = agent.Open
    agent.Open = function() called = true end
    sidebar._activate_under_cursor()
    agent.Open = orig_open
    assert.is_false(called)
  end)
end)

describe("sidebar cursor preservation", function()
   local sidebar, agent

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

   it("preserves cursor on the same (mode, idx) when entries reorder", function()
     local buf1 = vim.api.nvim_create_buf(false, true)
     local buf2 = vim.api.nvim_create_buf(false, true)
     agent._set_instance("opencode", 0, buf1, 9001)
     agent._set_instance("claude", 0, buf2, 9002)

     local orig = vim.fn.jobwait
     vim.fn.jobwait = function() return { -1 } end

     sidebar.open()
     sidebar.refresh()
     local data_start = sidebar._state().data_start_line
     -- Cursor lands on the second data row (claude)
     vim.api.nvim_win_set_cursor(sidebar._state().win, { data_start + 1, 0 })

     -- User is focused on the sidebar window
     vim.api.nvim_set_current_win(sidebar._state().win)

     -- Remove opencode; claude shifts to the first data row
     agent.instances.opencode = {}
     sidebar.refresh()

     local new_cursor = vim.api.nvim_win_get_cursor(sidebar._state().win)
     assert.equals(data_start, new_cursor[1])

     vim.fn.jobwait = orig
   end)
end)

describe("sidebar TermClose autocmd", function()
  local sidebar, agent

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

  it("registers a TermClose autocmd in the tw_agent_sidebar augroup", function()
    local autocmds = vim.api.nvim_get_autocmds({
      group = "tw_agent_sidebar",
      event = "TermClose",
    })
    assert.is_true(#autocmds >= 1)
    local has_agent_pattern = false
    for _, a in ipairs(autocmds) do
      if a.pattern == "agent://*" then has_agent_pattern = true end
    end
    assert.is_true(has_agent_pattern)
  end)

  it("does NOT register autocmds when enabled=false", function()
    sidebar.close()
    package.loaded["tw.agent.sidebar"] = nil
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = false })
    local ok, autocmds = pcall(vim.api.nvim_get_autocmds, {
      group = "tw_agent_sidebar",
      event = "TermClose",
    })
    if ok then
      assert.equals(0, #autocmds)
    end
  end)
end)

describe("sidebar drawer layout", function()
   local sidebar

  -- Track windows/buffers we create so after_each can clean them up.
  local created_wins = {}

  -- Open a window standing in for a file-explorer plugin. Defaults to
  -- nvim-tree's filetype (the explorer this config actually uses). Uses
  -- nvim_open_win directly (no :vsplit side effects) and wipes the buffer
  -- when the window closes.
  local function open_fake_nerdtree(filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = filetype or "NvimTree"
    local win = vim.api.nvim_open_win(buf, false, {
      split = "left",
      win = -1,
      width = 30,
    })
    table.insert(created_wins, win)
    return win
  end

  before_each(function()
    created_wins = {}
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
    for _, w in ipairs(created_wins) do
      if vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end)

  it("_find_nerdtree_win detects a nvim-tree (NvimTree) window", function()
    assert.is_nil(sidebar._find_nerdtree_win())
    local nt = open_fake_nerdtree("NvimTree")
    assert.equals(nt, sidebar._find_nerdtree_win())
  end)

  it("_find_nerdtree_win detects supported file-tree filetypes", function()
    for _, ft in ipairs({ "NvimTree", "nerdtree", "neo-tree" }) do
      local nt = open_fake_nerdtree(ft)
      assert.equals(nt, sidebar._find_nerdtree_win(), "should detect filetype=" .. ft)
      pcall(vim.api.nvim_win_close, nt, true)
    end
  end)

  it("_find_nerdtree_win returns nil when no nerdtree window exists", function()
    -- A plain split with a normal buffer must not be detected.
    vim.cmd("vsplit")
    local w = vim.api.nvim_get_current_win()
    table.insert(created_wins, w)
    assert.is_nil(sidebar._find_nerdtree_win())
  end)

  it("no NERDTree -> full-height split (taller than stacked height)", function()
    sidebar.open()
    local win = sidebar._state().win
    assert.is_true(vim.api.nvim_win_is_valid(win))
    -- A full-height split must be taller than the stacked height. The test
    -- editor (headless) is taller than that.
    assert.is_true(
      vim.api.nvim_win_get_height(win) > sidebar._stacked_height(),
      "full-height window should exceed stacked height"
    )
    -- Not stacked: winfixheight must NOT be set on the full-height path.
    assert.is_false(vim.wo[win].winfixheight)
  end)

  it("NERDTree present -> agents stacked below at fixed height", function()
    local nt = open_fake_nerdtree()
    sidebar.open()
    local win = sidebar._state().win
    assert.is_true(vim.api.nvim_win_is_valid(win))

    local nt_pos = vim.api.nvim_win_get_position(nt)   -- { row, col }
    local ag_pos = vim.api.nvim_win_get_position(win)

    -- Same left column: identical starting column.
    assert.equals(nt_pos[2], ag_pos[2])
    -- Agents below NERDTree: strictly greater row.
    assert.is_true(ag_pos[1] > nt_pos[1], "agents window should be below nerdtree")
    -- Fixed height exactly the stacked height (winfixheight makes this exact).
    assert.equals(sidebar._stacked_height(), vim.api.nvim_win_get_height(win))
  end)

  it("stacked window sets winfixheight", function()
    open_fake_nerdtree()
    sidebar.open()
    local win = sidebar._state().win
    assert.is_true(vim.wo[win].winfixheight)
  end)

  it("position='right' does NOT stack below NERDTree", function()
    package.loaded["tw.agent.sidebar"] = nil
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ position = "right" })
    open_fake_nerdtree()
    sidebar.open()
    local win = sidebar._state().win
    assert.is_true(vim.api.nvim_win_is_valid(win))
    -- Right-positioned sidebar must not stack: full-height, no winfixheight.
    assert.is_true(vim.api.nvim_win_get_height(win) > sidebar._stacked_height())
    assert.is_false(vim.wo[win].winfixheight)
  end)

  it("falls back to full-height when the stacked open fails", function()
    open_fake_nerdtree()
    local real_open_win = vim.api.nvim_open_win
    -- Force only the stacked ("below") open to fail; let other opens through.
    vim.api.nvim_open_win = function(buf, enter, cfg)
      if cfg and cfg.split == "below" then
        error("simulated stacked open failure")
      end
      return real_open_win(buf, enter, cfg)
    end

    local ok = pcall(sidebar.open)

    vim.api.nvim_open_win = real_open_win

    assert.is_true(ok, "open() should not propagate the stacked failure")
    local win = sidebar._state().win
    assert.is_true(vim.api.nvim_win_is_valid(win))
    -- Fallback is the full-height path: taller than stacked, no winfixheight.
    assert.is_true(vim.api.nvim_win_get_height(win) > sidebar._stacked_height())
    assert.is_false(vim.wo[win].winfixheight)
  end)

  it("does NOT reposition when NERDTree opens after the sidebar (known limitation)", function()
    -- Sidebar opens full-height first (no NERDTree). Repositioning is
    -- open-time only by design, so opening NERDTree afterwards must NOT
    -- move/reflow the already-open agents window.
    sidebar.open()
    local win = sidebar._state().win
    local before = vim.api.nvim_win_get_height(win)
    assert.is_true(before > sidebar._stacked_height()) -- full-height path

    open_fake_nerdtree()

    -- Same window handle, height unchanged: no reflow occurred.
    assert.equals(win, sidebar._state().win)
    assert.equals(before, vim.api.nvim_win_get_height(sidebar._state().win))
  end)

  it("calling open() twice with NERDTree present creates only one agents window", function()
    open_fake_nerdtree()
    sidebar.open()
    sidebar.open() -- second call must be a no-op
    local buf = sidebar._state().buf
    local count = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == buf then
        count = count + 1
      end
    end
    assert.equals(1, count)
  end)

  it("toggle close then reopen with NERDTree re-stacks at fixed height", function()
    local nt = open_fake_nerdtree()
    sidebar.toggle() -- open
    assert.equals(sidebar._stacked_height(), vim.api.nvim_win_get_height(sidebar._state().win))
    sidebar.toggle() -- close
    assert.is_nil(sidebar._state().win)
    sidebar.toggle() -- reopen
    local win = sidebar._state().win
    assert.is_true(vim.api.nvim_win_is_valid(win))
    local nt_pos = vim.api.nvim_win_get_position(nt)
    local ag_pos = vim.api.nvim_win_get_position(win)
    assert.equals(nt_pos[2], ag_pos[2])
    assert.is_true(ag_pos[1] > nt_pos[1])
    assert.equals(sidebar._stacked_height(), vim.api.nvim_win_get_height(win))
    assert.is_true(vim.wo[win].winfixheight)
  end)
end)

describe("sidebar lazy description generation", function()
  local sidebar, agent

  before_each(function()
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.agent.status"] = nil
    package.loaded["tw.agent.description"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    agent = helpers.reset_and_mock(false)
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({})
    pcall(sidebar.close)
  end)
  after_each(function()
    pcall(sidebar.close)
    package.loaded["tw.agent.description"] = nil
  end)

  it("refresh() calls generate() for nil descriptions", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test content" })
    agent._set_instance("opencode", 0, buf, 9001)

    local generate_called = false
    local generate_buf = nil

    package.loaded["tw.agent.description"] = {
      get = function(b)
        return nil -- Simulate not yet requested
      end,
      generate = function(b, callback)
        generate_called = true
        generate_buf = b
      end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig

    assert.is_true(generate_called)
    assert.equals(buf, generate_buf)
  end)

  it("refresh() does not call generate() for cached descriptions", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 9001)

    local generate_called = false

    package.loaded["tw.agent.description"] = {
      get = function(b)
        return "cached description"
      end,
      generate = function(b, callback)
        generate_called = true
      end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    vim.fn.jobwait = orig

    assert.is_false(generate_called)
  end)

  it("generate() callback triggers sidebar refresh", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })
    agent._set_instance("opencode", 0, buf, 9001)

    local stored_callback = nil
    local get_return = nil

    package.loaded["tw.agent.description"] = {
      get = function(b)
        return get_return
      end,
      generate = function(b, callback)
        stored_callback = callback
      end,
    }

    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end

    sidebar.open()
    sidebar.refresh()

    -- Simulate async completion
    get_return = "new description"
    if stored_callback then
      stored_callback("new description")
    end

    -- Give scheduled callback time to run
    vim.wait(50)

    vim.fn.jobwait = orig

    local lines = vim.api.nvim_buf_get_lines(sidebar._state().buf, 0, -1, false)
    assert.is_true(lines[3]:find("new description") ~= nil)
  end)
end)

describe("sidebar restorable entries", function()
  local sidebar, agent

  before_each(function()
    agent = helpers.reset_and_mock(false, {
      registry = {
        load = function()
          return {
            ["opencode#0"] = { mode = "opencode", idx = 0, cwd = "/wt",
              last_status = "restorable", description = "old task",
              session_id = "ses_side", updated_ts = os.time() },
          }
        end,
        upsert = function() end,
        _key_for = function(m, i) return string.format("%s#%d", m, i) end,
      },
    })
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = true })
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("includes registry entries with no live instance as restorable", function()
    local entries = sidebar._collect_entries("/wt")
    local found
    for _, e in ipairs(entries) do
      if e.mode == "opencode" and e.idx == 0 then found = e end
    end
    assert.is_not_nil(found)
    assert.equals("restorable", found.status)
    assert.is_true(found.restorable)
  end)

  it("does not duplicate a live instance as restorable", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 999)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    local entries = sidebar._collect_entries("/wt")
    vim.fn.jobwait = orig
    local count = 0
    for _, e in ipairs(entries) do
      if e.mode == "opencode" and e.idx == 0 then count = count + 1 end
    end
    assert.equals(1, count)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not show a restorable ghost for a dead but present instance (show_dead=false)", function()
    package.loaded["tw.agent.status"] = { detect = function() return "dead" end, invalidate = function() end }
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 999)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    local entries = sidebar._collect_entries("/wt")
    vim.fn.jobwait = orig
    package.loaded["tw.agent.status"] = nil
    for _, e in ipairs(entries) do
      if e.mode == "opencode" and e.idx == 0 then
        assert.is_false(e.restorable)
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("activates a restorable entry with resume args", function()
    package.loaded["tw.agent.resume"] = {
      args_for = function() return { "--session", "ses_x" } end,
    }
    local captured
    local orig_open = agent.Open
    agent.Open = function(mode, args, window_type, idx)
      captured = { mode = mode, args = args, window_type = window_type, idx = idx }
    end
    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    sidebar._activate_under_cursor()
    agent.Open = orig_open
    package.loaded["tw.agent.resume"] = nil
    assert.equals("opencode", captured.mode)
    assert.same({ "--session", "ses_x" }, captured.args)
    assert.equals(0, captured.idx)
  end)

  it("edit-under-cursor is a no-op for a restorable (nil-buf) entry", function()
    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    assert.has_no.errors(function()
      sidebar._edit_under_cursor()
    end)
  end)

  it("copies session_id onto restorable entries", function()
    local entries = sidebar._collect_entries("/wt")
    local found
    for _, e in ipairs(entries) do
      if e.mode == "opencode" and e.idx == 0 and e.restorable then found = e end
    end
    assert.is_not_nil(found)
    assert.equals("ses_side", found.session_id)
  end)

  it("forwards entry.session_id into resume.args_for on activate", function()
    local captured_opts
    package.loaded["tw.agent.resume"] = {
      args_for = function(_mode, _idx, _root, opts)
        captured_opts = opts
        return { "--session", "ses_side" }
      end,
    }
    local orig_open = agent.Open
    agent.Open = function() end
    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    sidebar._activate_under_cursor()
    agent.Open = orig_open
    package.loaded["tw.agent.resume"] = nil
    assert.is_not_nil(captured_opts)
    assert.equals("ses_side", captured_opts.session_id)
  end)
end)

describe("sidebar restorable supersession", function()
  local sidebar, agent

  before_each(function()
    agent = helpers.reset_and_mock(false, {
      registry = {
        load = function()
          return {
            ["opencode#0"] = { mode = "opencode", idx = 0, cwd = "/wt",
              last_status = "restorable", updated_ts = os.time() },
          }
        end,
        upsert = function() end,
        _key_for = function(m, i) return string.format("%s#%d", m, i) end,
      },
    })
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = true })
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("a live launch for a slot hides its restorable entry", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 999)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    local entries = sidebar._collect_entries("/wt")
    vim.fn.jobwait = orig
    for _, e in ipairs(entries) do
      if e.mode == "opencode" and e.idx == 0 then
        assert.is_false(e.restorable)
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("sidebar new session (a)", function()
  local sidebar, agent

  before_each(function()
    agent = helpers.reset_and_mock(false)
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = true })
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("returns 0 as the next free index when nothing is used", function()
    assert.equals(0, sidebar.next_free_index("opencode"))
  end)

  it("skips indices held by live instances", function()
    agent._set_instance("opencode", 0, vim.api.nvim_create_buf(false, true), 999)
    assert.equals(1, sidebar.next_free_index("opencode"))
  end)

  it("skips indices held by restorable registry entries", function()
    package.loaded["tw.agent.registry"] = {
      load = function()
        return {
          ["opencode#0"] = { mode = "opencode", idx = 0, updated_ts = os.time() },
          ["opencode#1"] = { mode = "opencode", idx = 1, updated_ts = os.time() },
        }
      end,
      upsert = function() end,
      _key_for = function(m, i) return string.format("%s#%d", m, i) end,
    }
    assert.equals(2, sidebar.next_free_index("opencode"))
  end)

  it("fills the lowest gap between used indices", function()
    agent._set_instance("opencode", 0, vim.api.nvim_create_buf(false, true), 999)
    agent._set_instance("opencode", 2, vim.api.nvim_create_buf(false, true), 998)
    assert.equals(1, sidebar.next_free_index("opencode"))
  end)

  it("opens a new default-mode session at the next free index", function()
    agent._set_instance("opencode", 0, vim.api.nvim_create_buf(false, true), 999)
    local captured
    local orig_open = agent.Open
    agent.Open = function(mode, args, window_type, idx)
      captured = { mode = mode, args = args, window_type = window_type, idx = idx }
    end
    sidebar.new_session()
    agent.Open = orig_open
    assert.equals("opencode", captured.mode)
    assert.equals(1, captured.idx)
    assert.is_nil(captured.args)
  end)

  it("'a' keymap invokes new-session", function()
    local called = false
    local orig = sidebar.new_session
    sidebar.new_session = function() called = true end
    sidebar.open()
    vim.api.nvim_buf_call(sidebar._state().buf, function()
      vim.cmd("normal a")
    end)
    sidebar.new_session = orig
    assert.is_true(called)
  end)
end)

describe("sidebar delete restorable (d)", function()
  local sidebar, agent, deleted

  before_each(function()
    deleted = {}
    agent = helpers.reset_and_mock(false, {
      registry = {
        load = function()
          return {
            ["opencode#0"] = { mode = "opencode", idx = 0, cwd = "/wt",
              last_status = "restorable", description = "old task",
              updated_ts = os.time() },
          }
        end,
        upsert = function() end,
        delete = function(_root, mode, idx)
          table.insert(deleted, { mode = mode, idx = idx })
        end,
        _key_for = function(m, i) return string.format("%s#%d", m, i) end,
      },
    })
    package.loaded["tw.agent.sidebar"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    sidebar = require("tw.agent.sidebar")
    sidebar.setup({ enabled = true })
  end)

  after_each(function()
    pcall(sidebar.close)
  end)

  it("deletes the restorable entry under the cursor", function()
    sidebar.open()
    sidebar.refresh()
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    sidebar.delete_under_cursor()
    assert.equals(1, #deleted)
    assert.equals("opencode", deleted[1].mode)
    assert.equals(0, deleted[1].idx)
  end)

  it("is a no-op for a live (non-restorable) entry", function()
    local buf = vim.api.nvim_create_buf(false, true)
    agent._set_instance("opencode", 0, buf, 999)
    local orig = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    sidebar.open()
    sidebar.refresh()
    vim.fn.jobwait = orig
    vim.api.nvim_win_set_cursor(sidebar._state().win, { sidebar._state().data_start_line, 0 })
    sidebar.delete_under_cursor()
    assert.equals(0, #deleted)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
