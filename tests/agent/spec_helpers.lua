-- Shared test helpers for agent specs.
local M = {}

-- Reset module state and install a tw.log mock that swallows all calls.
-- Must be called BEFORE the first require("tw.agent") in a test's
-- before_each. Returns the agent module for convenience.
--
-- opts.publish / opts.registry, when supplied, replace the default no-op stubs
-- for those modules so a test can spy on publisher calls. Stubs are installed
-- deterministically on every call (clearing any prior state) to keep tests
-- isolated across files.
function M.reset_and_mock(also_load_claude, opts)
  opts = opts or {}
  package.loaded["tw.agent"]        = nil
  package.loaded["tw.agent.claude"] = nil
  package.loaded["tw.log"]          = nil
  package.loaded["tw.log"] = {
    info  = function() end,
    warn  = function() end,
    error = function() end,
    debug = function() end,
  }
  package.loaded["tw.agent.registry"] = opts.registry or {
    load = function() return {} end,
    upsert = function() end,
    _key_for = function(m, i) return string.format("%s#%d", m, i) end,
  }
  package.loaded["tw.agent.publish"] = opts.publish or {
    record = function() end, record_exit = function() end,
    start_timer = function() end, stop_timer = function() end,
    push_status = function() end,
  }
  local agent = require("tw.agent")
  local claude_mod
  if also_load_claude then
    claude_mod = require("tw.agent.claude")
  end
  for mode, _ in pairs(agent.instances) do agent.instances[mode] = {} end
  agent.active_mode, agent.active_index = "none", 0
  agent.active_buf, agent.active_job_id = nil, nil
  return agent, claude_mod
end

-- Register an agent instance the way the product does, then drop the status
-- cache entry it just primed.
--
-- agent._set_instance publishes a record, and publishing detects the
-- instance's status. That detection runs against whatever vim.fn.jobwait is
-- installed at registration time -- normally the real one, which reports a
-- fake job id as dead -- and status.lua caches the answer per buffer for
-- 500ms. A test that installs its own jobwait stub afterwards would otherwise
-- read the stale "dead" instead of its stub, and would start passing on its
-- own once the cache aged out.
function M.set_instance(agent, mode, idx, buf, job_id)
  agent._set_instance(mode, idx, buf, job_id)
  local ok, status = pcall(require, "tw.agent.status")
  if ok and status and status.invalidate then
    status.invalidate(buf)
  end
end

-- Helper used by many tests
function M.buf_visible(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then return true end
  end
  return false
end

-- Close every window currently showing buf, leaving the buffer alive but
-- hidden. Refuses to close the last window in the tabpage.
function M.hide_buffer(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      if #vim.api.nvim_list_wins() > 1 then
        pcall(vim.api.nvim_win_close, win, false)
      end
    end
  end
end

-- Create a scratch buffer pre-filled with the given lines.
-- Useful for status-detection tests that need to scrape terminal-style
-- buffer contents without actually starting a job.
function M.mock_terminal_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if lines and #lines > 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return buf
end

return M
