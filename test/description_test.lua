-- Standalone unit tests for description module (pure logic, no plenary)
local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

-- Stub vim global for standalone tests
-- Minimal in-memory buffer implementation for testing
local buffer_store = {}
local next_buf_id = 1

_G.vim = {
    loop = {
        os_getenv = function(name)
            return nil -- For this module, env var lookup returns nil in tests
        end,
    },
    api = {
        nvim_create_buf = function(listed, scratch)
            local buf_id = next_buf_id
            next_buf_id = next_buf_id + 1
            buffer_store[buf_id] = { lines = {} }
            return buf_id
        end,
        nvim_buf_set_lines = function(buf, start, finish, strict_indexing, lines)
            if not buffer_store[buf] then
                buffer_store[buf] = { lines = {} }
            end
            buffer_store[buf].lines = lines
        end,
        nvim_buf_get_lines = function(buf, start, finish, strict_indexing)
            if not buffer_store[buf] then
                return nil
            end
            local all_lines = buffer_store[buf].lines
            if finish == -1 or finish > #all_lines then
                finish = #all_lines
            end
            if start < 0 then
                start = #all_lines + start + 1
            else
                start = start + 1
            end
            local result = {}
            for i = start, math.min(finish, #all_lines) do
                table.insert(result, all_lines[i])
            end
            return result
        end,
        nvim_buf_delete = function(buf, opts)
            buffer_store[buf] = nil
        end,
    },
    split = function(str, sep)
        local result = {}
        for segment in str:gmatch("([^" .. sep .. "]*)") do
            if segment ~= "" or #result == 0 then
                table.insert(result, segment)
            end
        end
        return result
    end,
    fn = {
        strchars = function(str)
            -- Simple UTF-8 char counter: count all bytes except continuation bytes
            local count = 0
            for i = 1, #str do
                local byte = string.byte(str, i)
                if byte < 128 or byte >= 192 then
                    count = count + 1
                end
            end
            return count
        end,
        strcharpart = function(str, start, len)
            -- Extract len characters starting at start (0-indexed)
            local chars = {}
            local char_idx = 0
            local i = 1
            while i <= #str do
                local byte = string.byte(str, i)
                local char_len = 1
                if byte >= 240 then char_len = 4
                elseif byte >= 224 then char_len = 3
                elseif byte >= 192 then char_len = 2
                end
                
                if char_idx >= start and char_idx < start + len then
                    table.insert(chars, str:sub(i, i + char_len - 1))
                end
                
                char_idx = char_idx + 1
                i = i + char_len
            end
            return table.concat(chars)
        end,
    },
    trim = function(str)
        return str:match("^%s*(.-)%s*$")
    end,
}

local function load_description()
    package.loaded["tw.agent.description"] = nil
    return require("tw.agent.description")
end

print("description module state management tests:")
print()

test("get() returns nil for buffer not in cache or loading", function()
    local description = load_description()
    description._reset_for_test()
    local result = description.get(123)
    eq(nil, result, "should return nil for uncached buffer")
end)

test("get() returns 'loading' when buffer is in loading set", function()
    local description = load_description()
    description._reset_for_test()
    description._set_loading_for_test(123, true)
    local result = description.get(123)
    eq("loading", result, "should return 'loading'")
end)

test("get() returns cached description when in cache", function()
    local description = load_description()
    description._reset_for_test()
    description._set_cache_for_test(123, "fixing tests")
    local result = description.get(123)
    eq("fixing tests", result, "should return cached description")
end)

test("get() returns 'error' when cached as error", function()
    local description = load_description()
    description._reset_for_test()
    description._set_cache_for_test(123, "error")
    local result = description.get(123)
    eq("error", result, "should return 'error'")
end)

test("invalidate() clears both cache and loading state", function()
    local description = load_description()
    description._reset_for_test()
    description._set_cache_for_test(123, "old description")
    description._set_loading_for_test(456, true)

    description.invalidate(123)
    description.invalidate(456)

    local r1 = description.get(123)
    local r2 = description.get(456)
    eq(nil, r1, "should clear cached description")
    eq(nil, r2, "should clear loading state")
end)

print("description ANSI stripping tests:")
print()

test("strips CSI sequences", function()
	local description = load_description()
	local input = "\27[31mred text\27[0m normal"
	local result = description._strip_ansi_for_test(input)
	eq("red text normal", result, "should strip ANSI color codes")
end)

test("strips OSC sequences with BEL terminator", function()
	local description = load_description()
	local input = "text\27]0;title\7more"
	local result = description._strip_ansi_for_test(input)
	eq("textmore", result, "should strip OSC with BEL")
end)

test("strips OSC sequences with ST terminator", function()
	local description = load_description()
	local input = "text\27]0;title\27\\more"
	local result = description._strip_ansi_for_test(input)
	eq("textmore", result, "should strip OSC with ST")
end)

test("handles text with no ANSI codes", function()
	local description = load_description()
	local input = "plain text"
	local result = description._strip_ansi_for_test(input)
	eq("plain text", result, "should return unchanged")
end)

print("description text extraction tests:")
print()

test("extracts first 75 lines from buffer", function()
	local description = load_description()
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}
	for i = 1, 100 do
		table.insert(lines, "line " .. i)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local result = description._extract_text_for_test(buf)
	local result_lines = vim.split(result, "\n")

	eq(75, #result_lines, "should be 75 lines")
	eq("line 1", result_lines[1], "first line should match")
	eq("line 75", result_lines[75], "75th line should match")

	vim.api.nvim_buf_delete(buf, { force = true })
end)

test("strips ANSI codes from extracted text", function()
	local description = load_description()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"\27[31mred\27[0m",
		"plain text",
	})

	local result = description._extract_text_for_test(buf)
	local has_red = result:find("red") ~= nil
	local has_escape = result:find("\27") ~= nil

	eq(true, has_red, "should contain 'red'")
	eq(false, has_escape, "should not contain escape code")

	vim.api.nvim_buf_delete(buf, { force = true })
end)

test("handles buffers with fewer than 75 lines", function()
	local description = load_description()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })

	local result = description._extract_text_for_test(buf)
	local result_lines = vim.split(result, "\n")

	eq(2, #result_lines, "should be 2 lines")

	vim.api.nvim_buf_delete(buf, { force = true })
end)

test("returns empty string for invalid buffer", function()
	local description = load_description()
	local result = description._extract_text_for_test(99999)
	eq("", result, "should return empty string")
end)

print("description truncation tests:")
print()

test("truncates ASCII text at 30 chars", function()
	local description = load_description()
	local input = "this is a very long description that exceeds thirty characters"
	local result = description._truncate_for_test(input, 30)
	eq("this is a very long descrip...", result, "should truncate to 30 chars")
	eq(30, vim.fn.strchars(result), "should be exactly 30 characters")
end)

test("does not truncate text shorter than limit", function()
	local description = load_description()
	local input = "short text"
	local result = description._truncate_for_test(input, 30)
	eq("short text", result, "should return unchanged")
end)

test("handles text exactly at limit", function()
	local description = load_description()
	local input = "exactly thirty characters!!!!!"
	local result = description._truncate_for_test(input, 30)
	eq("exactly thirty characters!!!!!", result, "should return unchanged")
end)

test("handles UTF-8 multi-byte characters safely", function()
	local description = load_description()
	local input = "测试中文字符串that is very long"
	local result = description._truncate_for_test(input, 20)
	eq(20, vim.fn.strchars(result), "should be exactly 20 characters")
	local ends_with_dots = result:sub(-3) == "..."
	eq(true, ends_with_dots, "should end with ...")
end)

test("handles empty string", function()
	local description = load_description()
	local result = description._truncate_for_test("", 30)
	eq("", result, "should return empty string")
end)

H.finish()
