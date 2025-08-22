local M = {}

-- Claude status component for lualine
local function claude_status()
	local ok, claude = pcall(require, "tw.claude")
	if not ok then
		return ""
	end

	local status = claude.get_status()
	if status.mode == "none" then
		return ""
	end

	-- Always use robot icon 🤖
	-- Alternative with nerd fonts (uncomment below if you have nerd fonts):
	-- local icon = ""  -- Robot icon from nerd fonts
	-- local icon = "󰚩"  -- Flag/marker icon
	-- local icon = ""  -- Brain icon

	local icon = "🤖" -- Robot emoji for Claude
	local mode_text = status.mode == "docker" and "Docker" or "Local"

	-- Include container name if in docker mode and running
	local details = ""
	if status.mode == "docker" and status.container_running and status.container_name then
		-- Show abbreviated container name (last 8 chars of the unique ID)
		local short_name = status.container_name:match("%-(%d+%-?%d*)$") or status.container_name
		details = " [" .. short_name .. "]"
	end

	return icon .. " " .. mode_text .. details
end

-- Setup lualine with Claude status
function M.setup_lualine(theme)
	theme = theme or "everforest"

	require("lualine").setup({
		options = {
			theme = theme,
			component_separators = { left = "", right = "" },
			section_separators = { left = "", right = "" },
		},
		sections = {
			lualine_a = { "mode" },
			lualine_b = { "branch", "diff", "diagnostics" },
			lualine_c = { "filename" },
			lualine_x = {
				claude_status, -- Add Claude status here
				"encoding",
				"fileformat",
				"filetype",
			},
			lualine_y = { "progress" },
			lualine_z = { "location" },
		},
		inactive_sections = {
			lualine_a = {},
			lualine_b = {},
			lualine_c = { "filename" },
			lualine_x = { "location" },
			lualine_y = {},
			lualine_z = {},
		},
		tabline = {},
		extensions = {},
	})
end

-- Alternative compact setup if you want a simpler integration
function M.get_claude_component()
	return {
		claude_status,
		-- Optional: add color configuration
		color = { fg = "#7aa2f7", bg = nil }, -- Blue text
		-- Optional: add conditions
		cond = function()
			local ok, claude = pcall(require, "tw.claude")
			if not ok then
				return false
			end
			local status = claude.get_status()
			return status.mode ~= "none"
		end,
	}
end

return M
