local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

local function load_module(opts)
	opts = opts or {}
	local system_calls = 0
	local conform_opts
	local buffer = {
		filetype = opts.filetype or "lua",
		modifiable = opts.modifiable ~= false,
	}

	_G.vim = {
		api = {
			nvim_buf_get_name = function()
				return "/tmp/example.lua"
			end,
			nvim_buf_is_valid = function()
				return opts.valid ~= false
			end,
			nvim_get_current_buf = function()
				return 7
			end,
		},
		bo = setmetatable({}, {
			__index = function()
				return buffer
			end,
		}),
		fs = {
			dirname = function()
				return "/tmp"
			end,
		},
		schedule_wrap = function(fn)
			return fn
		end,
		system = function(_, _, callback)
			system_calls = system_calls + 1
			callback({ code = 1, stdout = "" })
		end,
		tbl_contains = function(values, wanted)
			for _, value in ipairs(values) do
				if value == wanted then
					return true
				end
			end
			return false
		end,
		tbl_deep_extend = function(_, left, right)
			for key, value in pairs(right) do
				left[key] = value
			end
			return left
		end,
	}

	package.loaded["tw.log"] = { debug = function() end }
	package.loaded["conform"] = {
		format = function(format_opts)
			conform_opts = format_opts
		end,
	}
	package.loaded["tw.formatting"] = nil

	return require("tw.formatting"), function()
		return system_calls, conform_opts
	end
end

test("commit message buffers are not formatted after Fugitive writes them", function()
	local formatting, calls = load_module({ filetype = "gitcommit" })
	formatting.format()
	local system_calls, conform_opts = calls()
	eq(0, system_calls, "git calls")
	eq(nil, conform_opts, "conform options")
end)

test("non-modifiable buffers are not formatted", function()
	local formatting, calls = load_module({ modifiable = false })
	formatting.format()
	local system_calls, conform_opts = calls()
	eq(0, system_calls, "git calls")
	eq(nil, conform_opts, "conform options")
end)

test("async formatting stays attached to its originating buffer", function()
	local formatting, calls = load_module()
	formatting.format()
	local system_calls, conform_opts = calls()
	eq(1, system_calls, "git calls")
	eq(7, conform_opts.bufnr, "conform buffer")
end)

H.finish("Formatting tests")
