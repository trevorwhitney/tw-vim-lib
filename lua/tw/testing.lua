local M = {}

local function configre_vim_test()
  vim.g["test#custom_strategies"] = { aider = require("tw.aider").VimTestStrategy }
  vim.g["test#strategy"] = "dispatch"
  vim.g["test#go#gotest#options"] = "-v"
	vim.g["test#javascript#jest#options"] = "--no-coverage"
	-- vim.g["test#javascript#mocha#executable"] = "npm test --"
end

function M.setup()
	configre_vim_test()
end

return M
