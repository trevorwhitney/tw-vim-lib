local M = {}
local _options = {}

M.default_colorscheme = { light = "github_light", dark = "github_dark" }

function M.set(opts)
	_options = opts
end

function M.get()
	return _options
end

-- The colorscheme option is either a single name or a { light, dark } pair.
-- Normalize both shapes to a pair with neither side missing.
local function variants()
	local scheme = _options.colorscheme or M.default_colorscheme
	if type(scheme) == "string" then
		scheme = { light = scheme, dark = scheme }
	end

	return {
		light = scheme.light or scheme.dark,
		dark = scheme.dark or scheme.light,
	}
end

function M.colorscheme(background)
	local scheme = variants()
	return scheme[background] or scheme.dark
end

function M.colorschemes()
	local scheme = variants()
	if scheme.light == scheme.dark then
		return { scheme.dark }
	end

	return { scheme.dark, scheme.light }
end

return M
