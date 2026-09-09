local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

_G.vim = {
	env = {},
	v = { argv = { "nvim" } },
}

local events = require("tw.plugin-events")

test("normal launches retain VeryLazy events", function()
	eq("VeryLazy", events.very_lazy(), "normal startup event")
end)

test("plugin specs remain inspectable outside Neovim", function()
	local current_vim = vim
	_G.vim = nil
	eq("VeryLazy", events.very_lazy(), "plain Lua event")
	_G.vim = current_vim
end)

test("fullscreen launches wait for the agent process", function()
	vim.v.argv = { "nvim", "+AgentFullscreen opencode" }
	eq("User TwAgentStarted", events.very_lazy(), "fullscreen startup event")
	vim.v.argv = { "nvim" }
end)

test("fullscreen callbacks register for TwAgentStarted", function()
	local registration
	vim.v.argv = { "nvim", "+AgentFullscreen opencode" }
	vim.api = {
		nvim_create_autocmd = function(event, opts)
			registration = { event = event, opts = opts }
		end,
	}

	events.on_very_lazy(function() end)
	eq("User", registration.event, "autocmd event")
	eq("TwAgentStarted", registration.opts.pattern, "autocmd pattern")
	vim.v.argv = { "nvim" }
end)

test("Copilot plugins are not configured", function()
	local plugins = dofile("lua/tw/plugins/ai.lua")
	for _, plugin in ipairs(plugins) do
		local name = plugin[1] or ""
		eq(nil, name:match("[Cc]opilot"), "Copilot plugin " .. name)
	end
end)

test("DAP add-ons do not load at startup", function()
	local plugins = dofile("lua/tw/plugins/dap.lua")
	for _, plugin in ipairs(plugins) do
		local deferred = plugin.lazy == true
			or plugin.event ~= nil
			or plugin.cmd ~= nil
			or plugin.keys ~= nil
			or plugin.ft ~= nil
		eq(true, deferred, "deferred DAP plugin " .. tostring(plugin[1]))
	end
end)

test("tmux navigator loads lazily only inside tmux", function()
	vim.v.argv = { "nvim" }
	local plugins = dofile("lua/tw/plugins/navigation.lua")
	local navigator
	for _, plugin in ipairs(plugins) do
		if plugin[1] == "christoomey/vim-tmux-navigator" then
			navigator = plugin
			break
		end
	end

	eq("VeryLazy", navigator.event, "navigator startup event")
	vim.env.TMUX = nil
	eq(false, navigator.cond(), "outside tmux")
	vim.env.TMUX = "/tmp/tmux-501/default,1,0"
	eq(true, navigator.cond(), "inside tmux")
end)

H.finish("Startup plugin tests")
