local Typescript = {}

-- TODO: This is strictly setup for debugging jest test, might need expansion in the future
function Typescript.debug()
  local dap = require("dap")
  local filename = vim.fn.expand("%")
  local is_test = vim.api.nvim_eval('"' .. filename .. '" =~# g:test#javascript#jest#file_pattern')
  if is_test > 0 then
    Typescript.debug_test()
  else
    dap.continue()
  end
end

local function get_name(path, patterns)
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

  local nearest = vim.fn["test#base#nearest_test"](position, vim.g["test#javascript#patterns"])

  local namespace = table.concat(nearest["namespace"], " ")
  local test = table.concat(nearest["test"], " ")
  local name = namespace .. " " .. test

  local escaped_regex = vim.fn["substitute"](name, "\\([\\[\\].*+?|$^()]\\)", "\\\1", "g")

  return escaped_regex
end

function Typescript.debug_test()
  local dap = require("dap")
  local filename = vim.fn.expand("%")
  local test_name = get_name(filename)

  local runtimeArgs = {
    "./node_modules/jest/bin/jest.js",
    "--runInBand",
    "--no-coverage",
    "-t",
    test_name,
    filename,
  }

  for key, value in pairs(runtimeArgs) do
    print(key, value)
  end

  local config = {
    console = "integratedTerminal",
    cwd = "${workspaceFolder}",
    -- internalConsoleOptions = "neverOpen",
    protocol = "inspector",
    name = test_name,
    request = "launch",
    rootPath = "${workspaceFolder}",
    runtimeExecutable = "node",
    type = "pwa-node",
    runtimeArgs = runtimeArgs,
  }

  dap.run(config)
  -- open the console
  require("dapui").toggle(2)
end

return Typescript
