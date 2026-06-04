-- Shared test harness for the standalone Lua test suite (test/*_test.lua).
--
-- These tests run in plain `lua` (no Neovim). Each test file stubs whatever
-- `vim`/dependency surface it needs, requires this harness, registers cases
-- with `test(name, fn)`, then calls `H.finish()` to print results and exit
-- non-zero if anything failed.
--
-- Usage:
--   local H = dofile("test/harness.lua")
--   local test, eq = H.test, H.eq
--   test("does a thing", function() eq(1, 1, "one") end)
--   H.finish()

local H = {}

H.pass_count = 0
H.fail_count = 0

--- Register and immediately run a test case. Failures are captured (the run
--- continues) and reported in the summary.
--- @param name string
--- @param fn fun()
function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		H.pass_count = H.pass_count + 1
		print("  PASS: " .. name)
	else
		H.fail_count = H.fail_count + 1
		print("  FAIL: " .. name)
		print("        " .. tostring(err))
	end
end

--- Assert primitive equality.
--- @param expected any
--- @param actual any
--- @param msg string|nil
function H.eq(expected, actual, msg)
	if expected ~= actual then
		error(
			(msg or "")
				.. " expected: "
				.. tostring(expected)
				.. ", got: "
				.. tostring(actual)
		)
	end
end

--- Assert equality of two flat list-like tables (e.g. command arrays).
--- @param expected any[]
--- @param actual any[]
--- @param msg string|nil
function H.eq_list(expected, actual, msg)
	H.eq(#expected, #actual, (msg or "") .. " (length)")
	for i = 1, #expected do
		H.eq(expected[i], actual[i], (msg or "") .. " [" .. i .. "]")
	end
end

--- Print the results summary and exit non-zero if any test failed.
--- @param title string|nil optional header printed before the summary line
function H.finish(title)
	if title then
		print()
		print(title)
	end
	print()
	print(
		string.format(
			"Results: %d passed, %d failed, %d total",
			H.pass_count,
			H.fail_count,
			H.pass_count + H.fail_count
		)
	)
	if H.fail_count > 0 then
		os.exit(1)
	end
end

return H
