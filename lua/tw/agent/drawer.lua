-- Unified left "drawer": the file tree (nvim-tree) pinned top-left with the
-- agent sidebar stacked directly below it, opened and closed as one unit.
--
-- The tree always opens before the sidebar so the sidebar's open-time stacking
-- logic detects the tree window and slots in beneath it, regardless of the
-- order the user toggles things. This sidesteps nvim-tree's fixed top-left
-- placement, which would otherwise land left of an already-open sidebar.
local M = {}

-- nvim-tree backend. Wraps the public API so tests can inject a fake.
local default_tree = {
	open = function()
		require("nvim-tree.api").tree.open()
	end,
	close = function()
		require("nvim-tree.api").tree.close()
	end,
	is_open = function()
		local ok, api = pcall(require, "nvim-tree.api")
		if not ok then
			return false
		end
		return api.tree.is_visible()
	end,
}

local state = {
	tree = default_tree,
}

function M.setup(opts)
	opts = opts or {}
	if opts.tree then
		state.tree = opts.tree
	end
end

local function sidebar()
	return require("tw.agent.sidebar")
end

local function sidebar_is_open()
	local sb = sidebar()
	local st = sb._state and sb._state()
	return st ~= nil and st.win ~= nil and vim.api.nvim_win_is_valid(st.win)
end

-- The drawer is "open" if either half is showing.
function M.is_open()
	return state.tree.is_open() or sidebar_is_open()
end

function M.open()
	-- Tree first: the sidebar stacks below it on open.
	if not state.tree.is_open() then
		state.tree.open()
	end
	if not sidebar_is_open() then
		sidebar().open()
	end
end

function M.close()
	if sidebar_is_open() then
		sidebar().close()
	end
	if state.tree.is_open() then
		state.tree.close()
	end
end

function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

return M
