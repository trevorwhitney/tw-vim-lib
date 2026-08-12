-- Winbar-letter window picker (nvim-tree style), independent of agent
-- internals: callers pass window ids and get the chosen id back.
local M = {}

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function ensure_highlight()
	pcall(vim.api.nvim_set_hl, 0, "TwAgentWindowPicker", {
		bold = true,
		fg = "#1d2021",
		bg = "#fe8019",
		default = true,
	})
end

--- Prompt for one of the given windows by labeling each winbar with a letter.
--- Blocks on a single keypress and calls on_choice exactly once before
--- returning: the matching win id for an assigned letter (case-insensitive),
--- or nil for anything else (Esc, unassigned keys, multi-byte sequences,
--- empty input, or a getcharstr error).
function M.pick(win_ids, on_choice)
	if not win_ids or #win_ids == 0 then
		on_choice(nil)
		return
	end
	ensure_highlight()

	local saved = {}
	local letter_to_win = {}
	local labeled = math.min(#win_ids, #LETTERS)
	for i = 1, labeled do
		local win = win_ids[i]
		local letter = LETTERS:sub(i, i)
		letter_to_win[letter] = win
		saved[win] = vim.wo[win].winbar
		vim.wo[win].winbar = "%#TwAgentWindowPicker#%= " .. letter .. " %=%*"
	end

	vim.cmd("redraw")
	local ok, key = pcall(vim.fn.getcharstr)

	for win, winbar in pairs(saved) do
		pcall(function()
			vim.wo[win].winbar = winbar
		end)
	end

	-- Full-string, single-byte match only: a first-byte Esc check would
	-- half-match arrow-key sequences ("\27[A") and leak trailing bytes.
	if not ok or #key ~= 1 then
		on_choice(nil)
		return
	end
	on_choice(letter_to_win[key:upper()])
end

return M
