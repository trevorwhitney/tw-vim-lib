local Go = {}

function Go.configure_lsp(on_attach, capabilities)
  return {
    on_attach = on_attach,
    capabilities = capabilities,
    cmd = { "gopls", "serve" },
    flags = {
      debounce_text_changes = 150,
    },
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
        },
        buildFlags = { "-tags=requires_docker" },
        staticcheck = true,
      },
    },
    on_new_config = function(new_config, new_root_dir)
      local res = run_sync({ "go", "list", "-m" }, {
        cwd = new_root_dir,
      })
      if res.status_code ~= 0 then
        print("go list failed")
        return
      end

      new_config.settings.gopls["local"] = res.stdout
    end,
  }
end

function Go.debug_go_test(...)
  local dap = require("dap")
  local test_name = vim.fn["tw#go#testName"]()
  local tags = { ... }

  local config = {
    type = "go",
    name = test_name,
    request = "launch",
    mode = "test",
    program = "./${relativeFileDirname}",
    args = { "-test.run", test_name },
  }

  if #tags > 0 then
    config["buildFlags"] = "-tags=" .. table.concat(tags, ",")
  end

  dap.run(config)
end

function Go.runTest(...)
  local tags = { ... }
  vim.fn["tw#go#golangTestFocusedWithTags"](table.concat(tags, ","))
end

return Go
