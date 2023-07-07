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
        buildFlags = {
          "-tags=requires_docker,linux,cgo,promtail_journal_enabled",
        },
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

function Go.debug(...)
  local dap = require("dap")
  local filename = vim.fn.expand("%")
  if string.find(filename, "_test.go") then
    Go.debug_go_test(...)
  else
    dap.continue()
  end
end

function Go.remote_debug(path, port)
  local dap = require("dap")

  -- Get root of plugin directory
  local pluginRoot = debug.getinfo(1).source:sub(2):match("(.*tw[-]vim[-]lib).*")

  local goLaunchAdapter = {
    type = "executable",
    command = "node",
    args = { pluginRoot .. "/debug/go/debugAdapter.js" },
  }

  local goLaunchConfig = {
    type = "go",
    request = "attach",
    mode = "remote",
    name = "Remote Attached Debugger",
    dlvToolPath = vim.fn.system("which dlv"),
    remotePath = path,
    port = port,
    cwd = vim.fn.getcwd(),
  }

  local session = dap.launch(goLaunchAdapter, goLaunchConfig)
  if session == nil then
    io.write("Error launching adapter")
  end
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
