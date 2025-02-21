local Go = {}

function Go.configure_lsp(go_build_tags)
  return function(on_attach, capabilities)
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
            "-tags=" .. go_build_tags,
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
end

function Go.debug(test_name)
  local dap = require("dap")
  local filename = vim.fn.expand("%")
  if string.find(filename, "_test.go") then
    Go.debug_go_test(test_name)
  else
    dap.continue()
  end
end

-- adapt functions from vim-test to get the test name
local function get_name(path)
  local filename_modifier = vim.g["test#filename_modifier"] or ":."

  local position = {}
  position["file"] = vim.fn["fnamemodify"](path, filename_modifier)

  if path == vim.fn["expand"]("%") then
    position["line"] = vim.fn["line"](".")
  else
    position["line"] = 1
  end

  if path == vim.fn["expand"]("%") then
    position["col"] = vim.fn["col"](".")
  else
    position["col"] = 1
  end

  local nearest = vim.fn["test#base#nearest_test"](position, vim.g["test#go#patterns"])

  local parts = {}

  if nearest["namespace"] ~= nil and #nearest["namespace"] > 0 then
    table.insert(parts, table.concat(nearest["namespace"], "/"))
  end

  table.insert(parts, table.concat(nearest["test"], "/"))

  local name = table.concat(parts, "/")

  local without_spaces = vim.fn["substitute"](name, "\\s", "_", "g")
  local escaped_regex = vim.fn["substitute"](without_spaces, "\\([\\[\\].*+?|$^()]\\)", "\\\1", "g")

  return escaped_regex .. "$"
end

function Go.get_test_name(default)
  local filename = vim.fn.expand("%")
  if string.find(filename, "_test.go") then
    filename = get_name(filename)
  end

  --TODO: instead of a default, we should use telescope to present a list with all options
  return vim.fn.input({ prompt = "[Name] > ", default = default or filename })
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

function Go.debug_relative(args)
  local dap = require("dap")
  local program = vim.fn.fnamemodify(vim.fn.bufname(), ":p:h")
  local parent_dir = vim.fn.expand("%:p:h")
  local root = vim.fn.getcwd()

  local config = {
    type = "go",
    name = program,
    request = "launch",
    program = ".",
    cwd = parent_dir,
  }

  args = args or {}
  if #args > 0 then
    config["args"] = args
  end

  vim.cmd("cd " .. parent_dir)
  dap.run(config)
  vim.cmd("cd " .. root)
end

function Go.debug_go_test(test_name)
  local dap = require("dap")
  local name = test_name or get_name(vim.fn["expand"]("%"))

  -- TODO: if still needed, move to function like debug_with_flags
  -- local flags = { ... }
  local buildFlags = vim.fn["test#go#gotest#build_args"]({})

  local config = {
    type = "go",
    name = name,
    request = "launch",
    mode = "test",
    program = "./${relativeFileDirname}",
    args = { "-test.run", name },
  }

  if #buildFlags > 0 then
    config["buildFlags"] = table.concat(buildFlags, " ")
  end

  dap.run(config)
end

function Go.setupVimGo(go_build_tags)
  vim.g["go_code_completion_enabled"] = 0
  vim.g["go_def_mapping_enabled"] = 0
  vim.g["go_build_tags"] = go_build_tags
  vim.g["go_textobj_enabled"] = 0
  vim.g["go_gopls_enabled"] = 0
end

return Go

-- gopls available actions
--[[
"gopls.add_dependency",
"gopls.add_import",
"gopls.add_telemetry_counters",
"gopls.apply_fix",
"gopls.assembly",
"gopls.change_signature",
"gopls.check_upgrades",
"gopls.diagnose_files",
"gopls.doc",
"gopls.edit_go_directive",
"gopls.fetch_vulncheck_result",
"gopls.free_symbols",
"gopls.gc_details",
"gopls.generate",
"gopls.go_get_package",
"gopls.list_imports",
"gopls.list_known_packages",
"gopls.maybe_prompt_for_telemetry",
"gopls.mem_stats",
"gopls.regenerate_cgo",
"gopls.remove_dependency",
"gopls.reset_go_mod_diagnostics",
"gopls.run_go_work_command",
"gopls.run_govulncheck",
"gopls.run_tests",
"gopls.scan_imports",
"gopls.start_debugging",
"gopls.start_profile",
"gopls.stop_profile",
"gopls.test",
"gopls.tidy",
"gopls.toggle_gc_details",
"gopls.update_go_sum",
"gopls.upgrade_dependency",
"gopls.vendor",
"gopls.views",
"gopls.workspace_stats"
--]]
