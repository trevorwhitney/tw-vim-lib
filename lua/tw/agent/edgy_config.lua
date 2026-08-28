-- Title for a stacked agent pane. edgy renders the winbar per window and
-- exposes the rendering window via vim.g.statusline_winid, so the title can
-- reflect that pane's own agent (mode#idx) parsed from its agent:// buffer name.
local function agent_title()
	local win = vim.g.statusline_winid
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return "Agent"
	end
	local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
	local mode, idx = name:match("agent://(%w+)#(%d+)")
	if mode and idx then
		return mode .. "#" .. idx
	end
	return "Agent"
end

return {
	left = {
		{ ft = "NvimTree", title = "Files", size = { width = 40 } },
		-- Width is what this view used to inherit from the edgebar default, kept
		-- explicit now that the default is only a floor.
		{ ft = "tw-agent-sidebar", title = "Agents", size = { width = 30, height = 23 } },
	},
	right = {
		{ ft = "AgentConsole", title = agent_title, size = { width = 0.4 } },
	},
	-- edgy's stock value appends `Normal:EdgyNormal`, and it links EdgyNormal to
	-- NormalFloat, so every drawer renders against a darker background than the
	-- editor. Dropping that pair here means the mapping is never stamped onto a
	-- window at all; the winbar groups are kept so drawer titles keep their
	-- accent.
	wo = {
		winhighlight = "WinBar:EdgyWinBar,WinBarNC:EdgyWinBarNC",
	},
	-- An edgebar never shrinks below this, so edgy's stock 30 would snap a
	-- narrower drag straight back. Every view above sets its own width, leaving
	-- this purely a floor.
	options = {
		left = { size = 10 },
		right = { size = 10 },
	},
	keys = {
		["<c-q>"] = false,
		["<leader>q"] = function(win)
			require("tw.agent").CollapsePane(win)
		end,
		[">"] = function(win)
			win:resize("width", 2)
		end,
		["<lt>"] = function(win)
			win:resize("width", -2)
		end,
	},
}
