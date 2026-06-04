-- Standalone tests for buffer-util.should_autosave()
-- Run: lua test/buffer_util_test.lua (or via make test-lua)
--
-- Stubs vim so this runs outside Neovim. Each test installs a fresh vim
-- stub describing one buffer, then asserts the autosave decision.

local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

-- ---------------------------------------------------------------------------
-- vim stub builder
-- ---------------------------------------------------------------------------
-- Builds a minimal `vim` global describing a single buffer (always bufnr 1).
-- opts fields (all optional, sensible "happy path" defaults):
--   name        buffer name (default "/tmp/file.lua")
--   filetype    vim.bo filetype (default "lua")
--   buftype     vim.bo buftype (default "")
--   modifiable  vim.bo modifiable (default true)
--   readonly    vim.bo readonly (default false)
--   writable    whether filewritable() returns 1 (default true)
local function make_vim(opts)
	opts = opts or {}
	local function default(v, d)
		if v == nil then
			return d
		end
		return v
	end

	local name = default(opts.name, "/tmp/file.lua")
	local bo_entry = {
		filetype = default(opts.filetype, "lua"),
		buftype = default(opts.buftype, ""),
		modifiable = default(opts.modifiable, true),
		readonly = default(opts.readonly, false),
	}
	local writable = default(opts.writable, true)

	return {
		api = {
			nvim_get_current_buf = function()
				return 1
			end,
			nvim_buf_get_name = function(_bufnr)
				return name
			end,
		},
		bo = setmetatable({}, {
			__index = function(_, _bufnr)
				return bo_entry
			end,
		}),
		fn = {
			expand = function(s)
				return s
			end,
			filewritable = function(_path)
				return writable and 1 or 0
			end,
		},
		tbl_contains = function(list, value)
			for _, v in ipairs(list) do
				if v == value then
					return true
				end
			end
			return false
		end,
	}
end

-- Loads a fresh copy of the module under the given vim stub.
local function load_module(vim_stub)
	vim = vim_stub
	package.loaded["tw.buffer-util"] = nil
	return require("tw.buffer-util")
end

-- Adjust package.path to find our module
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

print("buffer-util.should_autosave tests:")
print()

-- ---------------------------------------------------------------------------
-- Happy path
-- ---------------------------------------------------------------------------
test("happy path: normal writable modifiable file returns true", function()
	local m = load_module(make_vim({}))
	eq(true, m.should_autosave(1), "should_autosave")
end)

-- ---------------------------------------------------------------------------
-- Early returns
-- ---------------------------------------------------------------------------
test("empty buffer name returns false", function()
	local m = load_module(make_vim({ name = "" }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("URI scheme (fugitive://) returns false", function()
	local m = load_module(make_vim({ name = "fugitive:///repo/.git//0/foo.lua" }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("URI scheme (octo://) returns false", function()
	local m = load_module(make_vim({ name = "octo://owner/repo/pull/1" }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("bracketed special name [dap-repl] returns false", function()
	local m = load_module(make_vim({ name = "[dap-repl]" }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

-- Each excluded filetype must return false.
local excluded_filetypes = {
	"aerial",
	"dap-repl",
	"dapui_console",
	"fugitive",
	"help",
	"nofile",
	"NvimTree",
	"qf",
	"quickfix",
	"telescope",
	"terminal",
	"trouble",
	"Trouble",
}
for _, ft in ipairs(excluded_filetypes) do
	test("excluded filetype '" .. ft .. "' returns false", function()
		local m = load_module(make_vim({ filetype = ft }))
		eq(false, m.should_autosave(1), "should_autosave")
	end)
end

test("non-empty buftype returns false", function()
	local m = load_module(make_vim({ buftype = "nofile" }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("non-modifiable buffer returns false", function()
	local m = load_module(make_vim({ modifiable = false }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("readonly buffer returns false", function()
	local m = load_module(make_vim({ readonly = true }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

test("non-writable file on disk returns false", function()
	local m = load_module(make_vim({ writable = false }))
	eq(false, m.should_autosave(1), "should_autosave")
end)

-- ---------------------------------------------------------------------------
-- bufnr defaulting
-- ---------------------------------------------------------------------------
test("nil bufnr defaults to current buffer", function()
	local m = load_module(make_vim({}))
	eq(true, m.should_autosave(nil), "should_autosave")
end)

H.finish()
