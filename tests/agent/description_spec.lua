local helpers = require("tests.agent.spec_helpers")

describe("description generation", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    helpers.reset_and_mock(false)
    description = require("tw.agent.description")
    description.reset()
  end)

  it("generate() returns immediately if already loading", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local call_count = 0

    -- Mock plenary.curl to track calls
    package.loaded["plenary.curl"] = {
      post = function()
        call_count = call_count + 1
      end,
    }

    -- Simulate buffer already loading
    description._set_loading(buf, true)

    -- Should be no-op
    description.generate(buf, function() end)

    assert.equals(0, call_count)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() returns immediately if API key missing", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local callback_called = false

    -- Force API key to be nil
    description._set_api_key(nil)

    description.generate(buf, function()
      callback_called = true
    end)

    assert.is_false(callback_called)
    assert.is_nil(description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() caches result on successful API response", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "working on tests" })

    description._set_api_key("test-key")

    -- Mock plenary.curl success
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        -- Simulate async callback
        vim.schedule(function()
          opts.callback({
            status = 200,
            body = vim.json.encode({
              content = { { text = "testing feature" } },
            }),
          })
        end)
      end,
    }

    local callback_result = nil
    description.generate(buf, function(result)
      callback_result = result
    end)

    -- Wait for async
    vim.wait(100, function()
      return callback_result ~= nil
    end)

    assert.equals("testing feature", callback_result)
    assert.equals("testing feature", description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() caches error on API failure", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })

    description._set_api_key("test-key")

    -- Mock plenary.curl error
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        vim.schedule(function()
          opts.callback({ status = 500, body = "error" })
        end)
      end,
    }

    local callback_result = nil
    description.generate(buf, function(result)
      callback_result = result
    end)

    vim.wait(100, function()
      return callback_result ~= nil
    end)

    assert.equals("error", callback_result)
    assert.equals("error", description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() does not cache error on rate limit (429)", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test" })

    description._set_api_key("test-key")

    -- Mock plenary.curl rate limit
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        vim.schedule(function()
          opts.callback({ status = 429, body = "rate limited" })
        end)
      end,
    }

    local callback_result = "not called"
    description.generate(buf, function(result)
      callback_result = result
    end)

    vim.wait(100, function()
      return callback_result ~= "not called"
    end)

    assert.is_nil(callback_result)
    assert.is_nil(description.get(buf)) -- Not cached
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("generate() requests a current, non-retired model", function()
    -- Regression guard: the original implementation used the retired model
    -- "claude-3-haiku-20240307", which returns HTTP 404 and surfaced as a
    -- silent "failed" in the UI. Pin the request to the known-good model.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test content" })

    description._set_api_key("test-key")

    local captured_body = nil
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        captured_body = opts.body
        vim.schedule(function()
          opts.callback({
            status = 200,
            body = vim.json.encode({ content = { { text = "ok" } } }),
          })
        end)
      end,
    }

    description.generate(buf, function() end)
    vim.wait(100, function()
      return captured_body ~= nil
    end)

    local payload = vim.json.decode(captured_body)
    assert.equals("claude-haiku-4-5-20251001", payload.model)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("description cleanup", function()
  local description

  before_each(function()
    package.loaded["tw.agent.description"] = nil
    helpers.reset_and_mock(false)
    description = require("tw.agent.description")
    description.reset()
  end)

  it("TermClose autocmd invalidates cache", function()
    -- Name the buffer to match the agent://* autocmd pattern.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "agent://opencode/0")

    -- Set a cached description
    description._set_cache(buf, "test description")
    assert.equals("test description", description.get(buf))

    -- Simulate TermClose for the agent buffer. The autocmd matches on the
    -- buffer name pattern; args.buf is set to the matched buffer.
    vim.api.nvim_exec_autocmds("TermClose", {
      buffer = buf,
    })

    -- Should be cleared
    assert.is_nil(description.get(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
