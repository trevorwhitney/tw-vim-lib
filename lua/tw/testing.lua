local M = {}

-- Resolve the project root for the current buffer's filetype by searching
-- upward for language-specific marker files, falling back to the cwd.
-- Exposed on M so it can be unit-tested (also used as vim's
-- `test#project_root` callback).
function M.get_test_project_root()
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

-- Without a multiplexer, :Dispatch falls back to running the command
-- synchronously and popping open a quickfix window. That window shrinks the
-- rows available to every edgebar, and the agent sidebar's fixed-height view
-- (lua/tw/agent/edgy_config.lua) doesn't fit what's left, so edgy throws
-- "Failed to layout windows". Closing the sidebar first keeps it out of that
-- layout pass; it reopens once Dispatch returns, synchronous case or not.
function M.dispatch(cmd)
	local sidebar = require("tw.agent.sidebar")
	local was_open = sidebar.is_open()
	if was_open then
		sidebar.close()
	end
	local ok, err = pcall(vim.cmd, "Dispatch " .. cmd)
	if was_open then
		sidebar.open()
	end
	if not ok then
		error(err, 0)
	end
end

local function configure_vim_test()
	vim.g["test#custom_strategies"] = {
		claude = require("tw.agent").VimTestStrategy,
		tw_dispatch = M.dispatch,
	}
	vim.g["test#strategy"] = "tw_dispatch"
	vim.g["test#go#gotest#options"] = "-v"
	vim.g["test#javascript#jest#options"] = "--no-coverage"
	-- Custom project root function for better test runner detection
	vim.g["test#project_root"] = M.get_test_project_root
end

function M.setup()
	configure_vim_test()
end
return M
