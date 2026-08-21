-- edgy only ever adds to a drawer window's window-local `winhighlight`, and
-- `winhighlight` outlives the buffer that earned it. A window that once held a
-- drawer therefore keeps rendering Normal as EdgyNormal (linked to NormalFloat,
-- a darker background) after an ordinary file replaces the drawer buffer in it.
-- Clearing the option alone does not hold: edgy re-stamps the window on
-- WinEnter from a per-window augroup that survives the window leaving the
-- edgebar.
local M = {}

-- The groups edgy maps into `winhighlight`. Matched whole so a window
-- highlight another plugin happens to point at an Edgy-prefixed group of its
-- own survives.
local edgy_groups = {
	EdgyNormal = true,
	EdgyWinBar = true,
	EdgyWinBarNC = true,
}

local drawer_filetypes

-- Filetypes edgy hosts: the views we register, plus the scratch buffer edgy
-- parks in a pinned-but-closed drawer.
local function is_drawer_filetype(filetype)
	if not drawer_filetypes then
		drawer_filetypes = { edgy = true }
		local config = require("tw.agent.edgy_config")
		for _, position in ipairs({ "left", "right", "top", "bottom" }) do
			for _, view in ipairs(config[position] or {}) do
				drawer_filetypes[type(view) == "table" and view.ft or view] = true
			end
		end
	end
	return drawer_filetypes[filetype] == true
end

local function edgy_get_win()
	local loaded, edgy = pcall(require, "edgy")
	return (loaded and type(edgy) == "table" and edgy.get_win) or nil
end

function M.strip(winhighlight)
	local kept = {}
	for entry in tostring(winhighlight or ""):gmatch("[^,]+") do
		local group = entry:match("^[^:]*:(.*)$")
		if not (group and edgy_groups[group]) then
			kept[#kept + 1] = entry
		end
	end
	return table.concat(kept, ",")
end

local function clean_window(win, get_win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local current = vim.wo[win].winhighlight or ""
	local stripped = M.strip(current)
	if stripped == current then
		return
	end

	-- A drawer filetype still in the window means edgy is mid-relayout rather
	-- than done with the window; bleaching it here would leave a live drawer
	-- with no way back to its own colours. edgy's own layout is global rather
	-- than per-tabpage, so this guard is what makes drawers on other tabpages
	-- safe to walk past.
	if is_drawer_filetype(vim.bo[vim.api.nvim_win_get_buf(win)].filetype) then
		return
	end
	if get_win then
		local called, owner = pcall(get_win, win)
		if called and owner ~= nil then
			return
		end
	end

	-- Reached only once edgy has dropped the window, so removing its re-stamp
	-- augroup cannot disturb a live drawer. edgy recreates the augroup if it
	-- ever adopts the window again.
	pcall(vim.api.nvim_del_augroup_by_name, "edgy_window_" .. win)
	vim.api.nvim_set_option_value("winhighlight", stripped, { scope = "local", win = win })
end

-- Every tabpage, not just the current one: winhighlight is window-local and
-- survives out of sight, so a background tabpage would otherwise show its stale
-- drawer colours for a frame when you switch to it.
function M.sweep()
	local get_win = edgy_get_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		clean_window(win, get_win)
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("TwEdgyWinhighlight", { clear = true })
	local pending = false

	-- Deferred so edgy has finished its own relayout and re-stamp for the
	-- event before the sweep decides which windows it still owns.
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "WinNew", "WinClosed" }, {
		group = group,
		callback = function()
			if pending then
				return
			end
			pending = true
			vim.schedule(function()
				pending = false
				M.sweep()
			end)
		end,
		desc = "Strip edgy drawer highlighting from windows edgy no longer owns",
	})
end

return M
