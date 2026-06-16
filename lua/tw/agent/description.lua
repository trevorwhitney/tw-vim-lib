local M = {}

-- Cache mapping buffer number to description string or "error"
local descriptions = {}

-- Set of buffer numbers currently generating descriptions (used as Lua set: buf -> true)
local loading = {}

-- Read API key once at module load to avoid repeated env lookups
local _api_key = vim.loop.os_getenv("ANTHROPIC_API_KEY")

-- Synchronous lookup of current description state
-- Returns: nil (not requested), "loading" (in progress), string (description), or "error"
function M.get(buf)
	if loading[buf] then
		return "loading"
	end
	return descriptions[buf] -- nil, string, or "error"
end

-- Clear cached description for a buffer
function M.invalidate(buf)
	descriptions[buf] = nil
	loading[buf] = nil
end

-- Test-only: reset all state
function M._reset_for_test()
	descriptions = {}
	loading = {}
end

-- Test-only: set loading state
function M._set_loading_for_test(buf, is_loading)
	loading[buf] = is_loading or nil
end

-- Test-only: set cached description
function M._set_cache_for_test(buf, value)
	descriptions[buf] = value
end

return M
