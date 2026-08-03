-- Standalone Lua test: asserts the edgy config contract (the three views we
-- register with edgy) without loading edgy or lazy.nvim.
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local cfg = require("tw.agent.edgy_config")

local function fail(msg)
	io.stderr:write("FAIL: " .. msg .. "\n")
	os.exit(1)
end

-- Collect { ft = position } across left + right edgebars.
local function collect(views, position, out)
	for _, v in ipairs(views or {}) do
		local ft = type(v) == "table" and v.ft or v
		out[ft] = position
	end
end

local ft_pos = {}
collect(cfg.left, "left", ft_pos)
collect(cfg.right, "right", ft_pos)

if ft_pos["NvimTree"] ~= "left" then
	fail("NvimTree must be a left view, got " .. tostring(ft_pos["NvimTree"]))
end
if ft_pos["tw-agent-sidebar"] ~= "left" then
	fail("tw-agent-sidebar must be a left view, got " .. tostring(ft_pos["tw-agent-sidebar"]))
end
if ft_pos["AgentConsole"] ~= "right" then
	fail("AgentConsole must be a right view, got " .. tostring(ft_pos["AgentConsole"]))
end

-- Tree must appear before the session sidebar in the left edgebar (top-to-bottom).
local left_order = {}
for i, v in ipairs(cfg.left) do
	left_order[type(v) == "table" and v.ft or v] = i
end
if not (left_order["NvimTree"] and left_order["tw-agent-sidebar"]
		and left_order["NvimTree"] < left_order["tw-agent-sidebar"]) then
	fail("NvimTree must be ordered above tw-agent-sidebar in the left edgebar")
end

print("ok - edgy_config contract")
