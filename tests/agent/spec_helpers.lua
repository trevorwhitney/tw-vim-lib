-- Shared test helpers for agent specs.
local M = {}

-- Reset module state and install a tw.log mock that swallows all calls.
-- Must be called BEFORE the first require("tw.agent") in a test's
-- before_each. Returns the agent module for convenience.
function M.reset_and_mock(also_load_claude)
  package.loaded["tw.agent"]        = nil
  package.loaded["tw.agent.claude"] = nil
  package.loaded["tw.log"]          = nil
  package.loaded["tw.log"] = {
    info  = function() end,
    warn  = function() end,
    error = function() end,
    debug = function() end,
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

-- Helper used by many tests
function M.buf_visible(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then return true end
  end
  return false
end

return M
