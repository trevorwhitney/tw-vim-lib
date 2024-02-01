local flexoki = require("flexoki")
local palette = require("flexoki.palette")
local c = palette.palette()

flexoki.colorscheme({
	variant = "light",
	highlight_groups = {
		["Search"] = { fg = c["bg"], bg = c["cy-2"] },
		["IncSearch"] = { fg = c["bg"], bg = c["cy-2"] },
		["Substitute"] = { fg = c["bg"], bg = c["cy-2"] },
	},
})
