require("tests.agent.spec_helpers")

local helpers = require("tests.agent.spec_helpers")

-- Regression: an opencode project root containing spaces (e.g. a Google Drive
-- path) must be shell-escaped when start_new_agent_job builds the command.
-- claude.command joins args with spaces into a single string for termopen, so
-- an unescaped path word-splits into extra positionals and opencode rejects the
-- arguments (prints help, exits 1).
describe("agent.opencode project path escaping", function()
  local agent
  local util
  local terminal
  local captured_cmd

  local root_with_spaces = "/Users/me/My Drive/grafana/Loki/wiki"

  before_each(function()
    agent = helpers.reset_and_mock(false)

    -- Stub on the already-loaded table instance so the upvalue captured by
    -- start_new_agent_job at module load resolves to our fake root.
    util = require("tw.agent.util")
    _G.__orig_get_git_root = util.get_git_root
    util.get_git_root = function() return root_with_spaces end

    terminal = require("tw.agent.terminal")
    _G.__orig_open_window = terminal.open_window
    _G.__orig_open_or_reuse = terminal.open_or_reuse_terminal_buffer
    _G.__orig_close_term = terminal.close_terminal_buffer
    terminal.open_window = function() end
    terminal.open_or_reuse_terminal_buffer = function() return false, nil end
    terminal.close_terminal_buffer = function() end

    captured_cmd = nil
    _G.__orig_termopen = vim.fn.termopen
    vim.fn.termopen = function(cmd, _opts)
      captured_cmd = cmd
      return 1
    end
  end)

  after_each(function()
    if _G.__orig_termopen then
      vim.fn.termopen = _G.__orig_termopen
      _G.__orig_termopen = nil
    end
    if util and _G.__orig_get_git_root then
      util.get_git_root = _G.__orig_get_git_root
      _G.__orig_get_git_root = nil
    end
    if terminal then
      terminal.open_window = _G.__orig_open_window
      terminal.open_or_reuse_terminal_buffer = _G.__orig_open_or_reuse
      terminal.close_terminal_buffer = _G.__orig_close_term
    end
  end)

  it("shell-escapes a project root that contains spaces", function()
    agent.Open("opencode", {}, "current", 0)

    assert.is_string(captured_cmd)

    local escaped = vim.fn.shellescape(root_with_spaces)
    assert.is_not_nil(
      captured_cmd:find(escaped, 1, true),
      "command should contain the shell-escaped root; got: " .. tostring(captured_cmd)
    )

    -- The root must appear only in escaped form, never as a bare positional
    -- that a shell would word-split. Strip the escaped occurrence and assert
    -- the raw path no longer appears anywhere.
    local without_escaped = captured_cmd:gsub(vim.pesc(escaped), "")
    assert.is_nil(
      without_escaped:find(root_with_spaces, 1, true),
      "raw unescaped path leaks into the command: " .. tostring(captured_cmd)
    )
  end)
end)
