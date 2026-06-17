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

-- Truncate text to max_chars, respecting UTF-8 boundaries
-- Appends "..." if truncated. Uses character count, not byte count.
local function truncate(text, max_chars)
	local char_count = vim.fn.strchars(text)
	if char_count <= max_chars then
		return text
	end

	-- Truncate to (max_chars - 3) to leave room for "..."
	-- vim.fn.strcharpart is UTF-8 aware
	local truncated = vim.fn.strcharpart(text, 0, max_chars - 3)
	return truncated .. "..."
end

-- Async generate description for buffer using Anthropic API
-- Calls callback(description_or_error) when complete
-- No-op if already loading or API key missing
function M.generate(buf, callback)
	-- Guard: already loading this buffer
	if loading[buf] then
		return
	end

	-- Guard: API key not configured
	if not api_key or api_key == "" then
		return
	end

	-- Mark as loading before async work
	loading[buf] = true

	-- Extract text from buffer
	local text = extract_text(buf)
	if text == "" then
		-- Invalid buffer or empty content
		descriptions[buf] = "error"
		loading[buf] = nil
		if callback then
			callback("error")
		end
		return
	end

	-- Build API request
	local ok, curl = pcall(require, "plenary.curl")
	if not ok then
		descriptions[buf] = "error"
		loading[buf] = nil
		if callback then
			callback("error")
		end
		return
	end

	local request_body = vim.json.encode({
		model = "claude-3-haiku-20240307",
		max_tokens = 30,
		messages = {
			{
				role = "user",
				content = "Summarize what this agent/terminal is doing in 4-5 words:\n\n" .. text,
			},
		},
	})

	curl.post("https://api.anthropic.com/v1/messages", {
		headers = {
			["x-api-key"] = api_key,
			["anthropic-version"] = "2023-06-01",
			["content-type"] = "application/json",
		},
		body = request_body,
		timeout = 10000,
		callback = function(response)
			vim.schedule(function()
				-- Remove from loading set
				loading[buf] = nil

				-- Handle response
				if response.status == 200 then
					local ok_parse, data = pcall(vim.json.decode, response.body)
					if ok_parse and data.content and data.content[1] and data.content[1].text then
						local desc = vim.trim(data.content[1].text)
						desc = truncate(desc, 30)
						descriptions[buf] = desc
						if callback then
							callback(desc)
						end
					else
						-- Malformed response
						descriptions[buf] = "error"
						if callback then
							callback("error")
						end
					end
				elseif response.status == 429 then
					-- Rate limit: don't cache error, allow retry
					if callback then
						callback(nil)
					end
				else
					-- Other error
					descriptions[buf] = "error"
					if callback then
						callback("error")
					end
				end
			end)
		end,
	})
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

-- Test-only: expose truncation
function M._truncate_for_test(text, max_chars)
	return truncate(text, max_chars)
end

-- Test-only: override API key
function M._set_api_key_for_test(key)
	api_key = key
end

return M
