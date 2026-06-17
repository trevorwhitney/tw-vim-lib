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
		model = "claude-haiku-4-5-20251001",
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
					-- Other error. Log status/body so failures are diagnosable
					-- instead of surfacing only a silent "failed" in the UI.
					local ok_log, log = pcall(require, "tw.log")
					if ok_log and log and log.warn then
						log.warn(
							string.format(
								"agent description request failed: status=%s body=%s",
								tostring(response.status),
								tostring(response.body)
							)
						)
					end
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

-- Reset all cached state. Mirrors status.reset(); used by tests and any
-- caller that needs a clean slate.
function M.reset()
	descriptions = {}
	loading = {}
end

-- Internal seams exposed for tests, following the M._foo convention used in
-- init.lua/sidebar.lua. The single underscore marks them as private/unstable.
M._strip_ansi = strip_ansi
M._extract_text = extract_text
M._truncate = truncate

-- Set the in-progress loading flag for a buffer (white-box state seam).
function M._set_loading(buf, is_loading)
	loading[buf] = is_loading or nil
end

-- Set the cached description for a buffer (white-box state seam).
function M._set_cache(buf, value)
	descriptions[buf] = value
end

-- Override the module-level API key (test seam; the key is normally read once
-- from the environment at module load).
function M._set_api_key(key)
	api_key = key
end

-- Register cleanup autocmd on module load
local augroup = vim.api.nvim_create_augroup("tw_agent_description_cleanup", { clear = true })
vim.api.nvim_create_autocmd("TermClose", {
	group = augroup,
	pattern = "agent://*",
	callback = function(args)
		M.invalidate(args.buf)
	end,
	desc = "Clear description cache when agent terminal exits",
})

return M
