require("tests.agent.spec_helpers")

local helpers = require("tests.agent.spec_helpers")

describe("agent.terminal", function()
  local terminal

  before_each(function()
    package.loaded["tw.agent.terminal"] = nil
    terminal = require("tw.agent.terminal")
  end)

  -- Track buffers/windows created during a test so we can tear them down even
  -- if an assertion fails partway through.
  local function cleanup_buf(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  describe("open_or_reuse_terminal_buffer", function()
    it("returns false, nil for a nil buffer", function()
      local ok, buf = terminal.open_or_reuse_terminal_buffer(nil, "vsplit")
      assert.is_false(ok)
      assert.is_nil(buf)
    end)

    it("returns false, nil for an invalid (deleted) buffer", function()
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(b, { force = true })
      local ok, buf = terminal.open_or_reuse_terminal_buffer(b, "vsplit")
      assert.is_false(ok)
      assert.is_nil(buf)
    end)

    it("focuses the existing window when the buffer is already visible", function()
      -- Make a buffer visible in a split, then move focus away from it.
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_command("vsplit")
      local target_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(target_win, b)
      -- Move to the other window so reuse has to switch focus back.
      vim.api.nvim_command("wincmd p")
      assert.are_not.equal(target_win, vim.api.nvim_get_current_win())

      local ok, buf = terminal.open_or_reuse_terminal_buffer(b, "vsplit")

      assert.is_true(ok)
      assert.equals(b, buf)
      -- Current window is now the one showing the buffer.
      assert.equals(b, vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()))

      vim.api.nvim_command("only")
      cleanup_buf(b)
    end)

    it("opens a hidden-but-valid buffer in a new window", function()
      -- Buffer exists but is not shown in any window.
      local b = vim.api.nvim_create_buf(false, true)
      assert.is_false(helpers.buf_visible(b))

      local ok, buf = terminal.open_or_reuse_terminal_buffer(b, "vsplit")

      assert.is_true(ok)
      assert.equals(b, buf)
      assert.is_true(helpers.buf_visible(b))

      vim.api.nvim_command("only")
      cleanup_buf(b)
    end)
  end)

  describe("close_terminal_buffer", function()
    it("closes windows showing the buffer and deletes it, returning nil, nil", function()
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_command("vsplit")
      vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), b)
      assert.is_true(helpers.buf_visible(b))

      local ret_buf, ret_job = terminal.close_terminal_buffer(b, nil)

      assert.is_nil(ret_buf)
      assert.is_nil(ret_job)
      assert.is_false(vim.api.nvim_buf_is_valid(b))
    end)

    it("is a no-op for a nil buffer (still returns nil, nil)", function()
      local ret_buf, ret_job = terminal.close_terminal_buffer(nil, nil)
      assert.is_nil(ret_buf)
      assert.is_nil(ret_job)
    end)

    it("is a no-op for an already-invalid buffer", function()
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(b, { force = true })
      local ret_buf, ret_job = terminal.close_terminal_buffer(b, nil)
      assert.is_nil(ret_buf)
      assert.is_nil(ret_job)
    end)

    it("stops a running job before deleting the buffer", function()
      -- Stub jobwait/jobstop to drive the job-stop branch without a real job.
      local orig_jobwait = vim.fn.jobwait
      local orig_jobstop = vim.fn.jobstop
      local stopped = {}
      vim.fn.jobwait = function(_ids, _timeout)
        return { -1 } -- -1 == still running
      end
      vim.fn.jobstop = function(id)
        table.insert(stopped, id)
        return 1
      end

      local b = vim.api.nvim_create_buf(false, true)
      local fake_job = 4242

      local ok, err = pcall(function()
        terminal.close_terminal_buffer(b, fake_job)
      end)

      vim.fn.jobwait = orig_jobwait
      vim.fn.jobstop = orig_jobstop

      assert.is_true(ok, tostring(err))
      assert.same({ fake_job }, stopped)
      assert.is_false(vim.api.nvim_buf_is_valid(b))
    end)

    it("does not stop a job that has already exited", function()
      local orig_jobwait = vim.fn.jobwait
      local orig_jobstop = vim.fn.jobstop
      local stop_called = false
      vim.fn.jobwait = function(_ids, _timeout)
        return { 0 } -- 0 == job already exited
      end
      vim.fn.jobstop = function(_id)
        stop_called = true
      end

      local b = vim.api.nvim_create_buf(false, true)
      terminal.close_terminal_buffer(b, 99)

      vim.fn.jobwait = orig_jobwait
      vim.fn.jobstop = orig_jobstop

      assert.is_false(stop_called)
      cleanup_buf(b)
    end)
  end)
end)
