local M = {}

-- Filetypes that live in the edgy sidebars/drawers and are never valid targets
-- for opening a file: the agent terminals, the file tree, and the agent list.
local non_editor_filetypes = {
	AgentConsole = true,
	NvimTree = true,
	["tw-agent-sidebar"] = true,
}

-- A window is an editor pane if it holds an ordinary buffer (not one of the
-- edgy-managed sidebars) and is not floating. Floating windows (pickers,
-- popups) must never receive a gf'd file.
local function is_editor_win(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local cfg = vim.api.nvim_win_get_config(win)
	if cfg.relative and cfg.relative ~= "" then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return not non_editor_filetypes[vim.bo[buf].filetype]
end

-- Find an editor pane in the current tabpage, preferring the most recently
-- used one (via the jump order returned by nvim_tabpage_list_wins puts the
-- current window first). Returns nil when only sidebar/agent windows exist.
function M.find_editor_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if is_editor_win(win) then
			return win
		end
	end
	return nil
end

-- Open path in an editor pane: reuse an existing one if present, otherwise
-- create a vertical split on the far left (topleft) so the agent drawer on the
-- right is left untouched.
function M.open_in_editor_pane(path)
	local win = M.find_editor_win()
	if win then
		vim.api.nvim_set_current_win(win)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
	else
		vim.cmd("vertical topleft split " .. vim.fn.fnameescape(path))
	end
end

-- Buffer-local gf handler for AgentConsole terminals: resolve the file under
-- the cursor and open it in an editor pane instead of replacing the agent.
function M.gf()
	local cfile = vim.fn.expand("<cfile>")
	if not cfile or cfile == "" then
		return
	end
	local found = vim.fn.findfile(cfile)
	local path = (found ~= "" and found) or cfile
	M.open_in_editor_pane(path)
end

return M
