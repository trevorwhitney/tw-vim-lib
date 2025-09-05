local M = {}

local function get_test_project_root()
  local ft = vim.bo.filetype
  local markers = {}

  -- Define markers for each language
  if ft == "javascript" or ft == "typescript" or ft == "typescriptreact" or ft == "javascriptreact" then
    markers = { "package.json" }
  elseif ft == "go" then
    markers = { "go.mod" }
  elseif ft == "ruby" then
    markers = { "Gemfile", ".ruby-version" }
  elseif ft == "python" then
    markers = { "setup.py", "pyproject.toml", "requirements.txt", "Pipfile" }
  elseif ft == "rust" then
    markers = { "Cargo.toml" }
  elseif ft == "java" or ft == "groovy" or ft == "kotlin" then
    markers = { "build.gradle", "build.gradle.kts", "pom.xml" }
  end

  -- Search for markers
  for _, marker in ipairs(markers) do
    local found = vim.fn.findfile(marker, ".;")
    if found ~= "" then
      return vim.fn.fnamemodify(found, ":h")
    end
  end

  -- Default: use current working directory
  return vim.fn.getcwd()
end


local function configure_vim_test()
	vim.g["test#custom_strategies"] = {
		claude = require("tw.claude").VimTestStrategy,
	}
	vim.g["test#strategy"] = "dispatch"
	vim.g["test#go#gotest#options"] = "-v"
	vim.g["test#javascript#jest#options"] = "--no-coverage"
  -- Custom project root function for better test runner detection
  vim.g["test#project_root"] = get_test_project_root
end

function M.setup()
  configure_vim_test()
end
return M
