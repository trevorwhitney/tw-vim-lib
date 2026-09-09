local H = dofile("test/harness.lua")
local test, eq = H.test, H.eq

local plugins = dofile("lua/tw/plugins/ui.lua")

test("GitHub theme uses GitHub-style diff backgrounds", function()
	local github_theme
	for _, plugin in ipairs(plugins) do
		if plugin.name == "github-theme" then
			github_theme = plugin
			break
		end
	end

	eq(false, github_theme.opts.options.modules.diffchar, "diffchar module")
	local groups = github_theme.opts.groups.all
	eq("palette.success.subtle", groups.DiffAdd.bg, "added line background")
	eq("palette.danger.subtle", groups.DiffDelete.bg, "deleted line background")
	eq("palette.attention.subtle", groups.DiffChange.bg, "changed line background")
	local diff_text = groups.DiffText
	eq("palette.attention.muted", diff_text.bg, "DiffText background")
	eq(nil, diff_text.fg, "DiffText preserves syntax foreground")
	eq("palette.success.muted", groups.TwDiffviewAddText.bg, "added text background")
	eq("palette.danger.muted", groups.TwDiffviewDeleteText.bg, "deleted text background")
end)

H.finish("UI plugin tests")
