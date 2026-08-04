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

-- Look up a view by filetype across an edgebar list.
local function find_view(views, ft)
	for _, v in ipairs(views or {}) do
		if type(v) == "table" and v.ft == ft then
			return v
		end
	end
	return nil
end

local agent_console = find_view(cfg.right, "AgentConsole")
if not (agent_console and agent_console.size and agent_console.size.width == 160) then
	fail("AgentConsole width must be 160, got " .. tostring(agent_console and agent_console.size and agent_console.size.width))
end

if cfg.keys["<c-q>"] ~= false then
	fail("<c-q> must be disabled (false) to avoid the tmux prefix conflict")
end
if type(cfg.keys["<leader>q"]) ~= "function" then
	fail("<leader>q must be a function that hides the edgy window")
end
if type(cfg.keys[">"]) ~= "function" then
	fail("> must be a function that grows the edgy window width")
end
if type(cfg.keys["<lt>"]) ~= "function" then
	fail("<lt> must be a function that shrinks the edgy window width")
end

-- Fake Edgy.Window recording the resize/hide calls the keymaps make.
local function fake_win()
	local win = { resized = nil, hidden = false }
	function win:resize(dim, amount)
		self.resized = { dim = dim, amount = amount }
	end
	function win:hide()
		self.hidden = true
	end
	return win
end

local grow = fake_win()
cfg.keys[">"](grow)
if not (grow.resized and grow.resized.dim == "width" and grow.resized.amount > 0) then
	fail("> must grow width by a positive amount")
end

local shrink = fake_win()
cfg.keys["<lt>"](shrink)
if not (shrink.resized and shrink.resized.dim == "width" and shrink.resized.amount < 0) then
	fail("<lt> must shrink width by a negative amount")
end

local hide = fake_win()
cfg.keys["<leader>q"](hide)
if not hide.hidden then
	fail("<leader>q must hide the edgy window")
end

print("ok - edgy_config contract")
