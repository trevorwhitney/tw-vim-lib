local M = {}
local api = vim.api

function M.setup()
	-- TODO: this is broken on mac because it's hardcoded to xdg-open
	api.nvim_create_user_command(
		"Browse",
		"silent exe '!xdg-open \"' . tw#util#UrlEscape(<q-args>) . '\"'",
		{ bang = true, nargs = 1 }
	)

	api.nvim_create_user_command("Gpr", "Git pull --rebase", { bang = true, nargs = 0 })

	api.nvim_create_user_command("Gpp", require("tw.config.Git").gpp, { bang = true, nargs = 0 })
end

return M
