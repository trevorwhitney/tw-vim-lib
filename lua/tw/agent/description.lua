local M = {}

-- Cache mapping buffer number to description string or "error"
local descriptions = {}

-- Set of buffer numbers currently generating descriptions (used as Lua set: buf -> true)
local loading = {}

-- Read API key once at module load to avoid repeated env lookups
local api_key = vim.loop.os_getenv("ANTHROPIC_API_KEY")

-- Strip ANSI escape sequences from text
-- Removes ANSI escape sequences including CSI, OSC, and two-byte codes
local function strip_ansi(s)
	-- CSI: ESC [ <params/intermediates> <final-byte>
	s = s:gsub("\27%[[%d;:%?%>%<]*[ -/]*[A-Za-z@%[\\%]^_`{|}~]", "")
	-- OSC: ESC ] <anything except BEL or ESC> <terminator>
	-- Terminators: BEL (\7) or ESC \ (ST)
	s = s:gsub("\27%][^\7\27]*\7", "")
	s = s:gsub("\27%][^\27]*\27\\", "")
	-- Two-byte ESC sequences: ESC <single letter or = > >
	s = s:gsub("\27[=>%(%)#%*+%-./]", "")
	return s
end

-- Extract first 75 lines from terminal buffer and strip ANSI codes
-- Returns joined text or empty string if buffer invalid
local function extract_text(buf)
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, 75, false)
	if not ok or not lines then
		return ""
	end
	local joined = table.concat(lines, "\n")
	return strip_ansi(joined)
end

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

-- Test-only: expose ANSI stripping
function M._strip_ansi_for_test(s)
	return strip_ansi(s)
end

-- Test-only: expose text extraction
function M._extract_text_for_test(buf)
	return extract_text(buf)
end

return M
