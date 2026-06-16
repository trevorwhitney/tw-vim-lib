-- Standalone unit tests for description module (pure logic, no plenary)
local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

-- Stub vim global for standalone tests
_G.vim = {
    loop = {
        os_getenv = function(name)
            return nil -- For this module, env var lookup returns nil in tests
        end,
    },
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

H.finish()
