local M = {}

-- Agent status component for lualine. Renders [<mode>#<idx>] when an
-- agent instance is active; empty string otherwise.
local function agent_status()
	local ok, agent = pcall(require, "tw.agent")
	if not ok then
		return ""
	end
	local status = agent.get_status()
	if not status or status.mode == "none" then
		return ""
	end
	return string.format("[%s#%d]", status.mode, status.index or 0)
end

-- Setup lualine with the agent status indicator.
function M.setup_lualine(theme)
	theme = theme or "auto"

	require("lualine").setup({
		options = {
			theme = theme,
			component_separators = { left = "", right = "" },
			section_separators = { left = "", right = "" },
		},
		sections = {
			lualine_a = {
				{
					"mode",
					-- Give TERMINAL mode its own color so it is distinct from NORMAL.
					color = function()
						if vim.fn.mode() == "t" then
							return { bg = "#98bb6c", fg = "#1f1f28", gui = "bold" }
						end
						return nil
					end,
				},
			},
			lualine_b = { "branch", "diff", "diagnostics" },
			lualine_c = { "filename" },
			lualine_x = {
				agent_status,
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

-- Compact lualine component for callers that want to pick and place the
-- agent indicator themselves.
function M.get_agent_component()
	return {
		agent_status,
		color = { fg = "#7aa2f7", bg = nil },
		cond = function()
			local ok, agent = pcall(require, "tw.agent")
			if not ok then
				return false
			end
			local status = agent.get_status()
			return status and status.mode ~= "none"
		end,
	}
end

return M
