local flexoki = require("flexoki")
local palette = require("flexoki.palette")
local c = palette.palette()

local highlight_groups = {
	["Search"] = { fg = c["bg"], bg = c["cy-2"] },
	["IncSearch"] = { fg = c["bg"], bg = c["cy-2"] },
	["Substitute"] = { fg = c["bg"], bg = c["cy-2"] },
	["NvimInternalError"] = { fg = c["bg"], bg = c["re-2"] },
	["MiniTrailspace"] = { fg = c["bg"], bg = c["re-2"] },
	["WinSeparator"] = { fg = c["fg"], bg = c["bg-2"] },
	["WinSeparatorNC"] = { fg = c["fg"], bg = c["bg-2"] },
	["FloatShadow"] = { fg = c["bg"], bg = c["tx"] },
	["FloatShadowThrough"] = { fg = c["bg"], bg = c["tx"] },
	["DapUIPlayPauseNC"] = { fg = c["gr-2"], bg = c["ui"] },
	["DapUIRestartNC"] = { fg = c["gr-2"], bg = c["ui"] },
	["LspReferenceRead"] = { fg = c["tx"], bg = c["ui-3"] },
	["LspReferenceText"] = { fg = c["tx"], bg = c["ui-3"] },
	["LspReferenceWrite"] = { fg = c["tx"], bg = c["ui-3"] },
	["NvimTreeCursorLine"] = { fg = c["tx"], bg = c["ui-3"] },
}

if vim.o.background == "dark" then
	highlight_groups = {}
end

flexoki.colorscheme({
	variant = vim.o.background,
	highlight_groups = highlight_groups,
})
