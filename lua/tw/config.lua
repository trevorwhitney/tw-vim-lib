local M = {}
local _options = {}

function M.set(opts)
	_options = opts
end

function M.get()
	return _options
end

return M
