local M = {}
local _options = {}

M.default_colorscheme = "github_light"

function M.set(opts)
	_options = opts
end

function M.get()
	return _options
end

function M.colorscheme()
	return _options.colorscheme or M.default_colorscheme
end

return M
