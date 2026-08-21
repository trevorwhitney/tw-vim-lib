-- edgy owns the thickness of an edgebar: on every WinResized it recomputes the
-- bar from its configured sizes and writes the result straight back, so a
-- separator dragged with the mouse is undone before the next redraw. edgy does
-- accept a new thickness, but only as the window-local `edgy_width` /
-- `edgy_height` override its own resize keymaps set, so a drag has to be
-- translated into that override.
local M = {}

-- Space kept for the rest of the editor. A terminal too small to honour the
-- bar's size is the one thing besides the user that moves a pinned dimension,
-- and it always leaves the bar filling nearly the whole screen. Refusing those
-- sizes stops a briefly-narrow terminal from pinning the bar narrow for the
-- rest of the session.
local MIN_REMAINDER = 10

local function edgy_window(win)
	local loaded, edgy = pcall(require, "edgy")
	if not (loaded and type(edgy) == "table" and edgy.get_win) then
		return nil
	end
	local called, window = pcall(edgy.get_win, win)
	return called and window or nil
end

local function animating()
	local loaded, animate = pcall(require, "edgy.animate")
	return loaded and animate.is_active() == true
end

-- The size the user dragged this edgebar to, or nil if the change was edgy's.
local function dragged_size(window, edgebar)
	if not vim.api.nvim_win_is_valid(window.win) then
		return nil
	end

	local vertical = edgebar.vertical

	-- edgy pins the shared dimension, so opening a split, `wincmd =` and a
	-- terminal resize all leave it where it was. Anything that still moved it
	-- was an explicit resize, and the mouse is the only one the user did not
	-- already route through edgy.
	if not vim.wo[window.win][vertical and "winfixwidth" or "winfixheight"] then
		return nil
	end

	-- Set by edgy's own layout pass; absent until the bar has been laid out once.
	local target = window[vertical and "width" or "height"]
	if type(target) ~= "number" then
		return nil
	end

	local actual = vertical and vim.api.nvim_win_get_width(window.win) or vim.api.nvim_win_get_height(window.win)
	if actual == target or actual > (vertical and vim.o.columns or vim.o.lines) - MIN_REMAINDER then
		return nil
	end
	return actual
end

---@param wins number[] the windows WinResized reported
function M.adopt(wins)
	-- edgy's own sizing lands here too. WinResized is emitted from the main
	-- loop, after edgy has already restored `eventignore`, so its `noautocmd`
	-- wrapper does not hide the animation frames it writes on the way to the
	-- target size; by size alone those look exactly like a drag.
	if animating() then
		return
	end

	local handled = {}
	for _, win in ipairs(wins or {}) do
		local window = edgy_window(win)
		local edgebar = window and window.view.edgebar
		if edgebar and not handled[edgebar] then
			handled[edgebar] = true
			local size = dragged_size(window, edgebar)
			if size then
				-- edgy sizes an edgebar to its thickest window, so the drag has
				-- to reach every window sharing the bar or the old size wins.
				local override = "edgy_" .. (edgebar.vertical and "width" or "height")
				for _, sibling in ipairs(edgebar.wins) do
					vim.w[sibling.win][override] = size
				end
			end
		end
	end
end

-- Must be called before `edgy.setup()`: autocmds run in registration order, and
-- this one has to read the dragged size before edgy's own WinResized handler
-- recomputes the bar and overwrites it.
function M.setup()
	local group = vim.api.nvim_create_augroup("TwEdgyMouseResize", { clear = true })
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			M.adopt(vim.v.event.windows)
		end,
		desc = "Keep a mouse-dragged edgebar at the size it was dragged to",
	})
end

return M
