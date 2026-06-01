require("tests.agent.spec_helpers")

describe("buffer-config last_change_at tracking", function()
  local buffer_config

  before_each(function()
    -- Standardized reset: drop the module from package.loaded so the next
    -- require returns a fresh module table with empty buffer_states.
    package.loaded["tw.agent.buffer-config"] = nil
    package.loaded["tw.log"] = {
      info = function() end, warn = function() end,
      error = function() end, debug = function() end,
    }
    buffer_config = require("tw.agent.buffer-config")
  end)

  it("setup_buffer initializes last_change_at to nil", function()
    local buf = vim.api.nvim_create_buf(false, true)
    buffer_config.setup_buffer(buf, {})
    assert.is_nil(buffer_config.buffer_states[buf].last_change_at)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("TextChanged autocmd updates last_change_at", function()
    local buf = vim.api.nvim_create_buf(false, true)
    buffer_config.setup_buffer(buf, {})
    -- Simulate the autocmd firing by invoking it directly
    vim.api.nvim_buf_call(buf, function()
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    end)
    assert.is_number(buffer_config.buffer_states[buf].last_change_at)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("cleanup marks buffer state inactive (full nil is deferred 5s)", function()
    -- buffer-config.cleanup() defers the nil-out via vim.defer_fn(..., 5000)
    -- so synchronously we only see active=false. Verify that path here.
    local buf = vim.api.nvim_create_buf(false, true)
    buffer_config.setup_buffer(buf, {})
    buffer_config.buffer_states[buf].last_change_at = 12345
    buffer_config.cleanup(buf)
    assert.is_table(buffer_config.buffer_states[buf])
    assert.is_false(buffer_config.buffer_states[buf].active)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
