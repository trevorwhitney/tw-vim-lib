local H = dofile("test/harness.lua")
local test, eq, eq_list = H.test, H.eq, H.eq_list

test("uses the maintained Diffview fork", function()
	local plugins = dofile("lua/tw/plugins/git.lua")
	eq("dlyongemallo/diffview-plus.nvim", plugins[3][1])
end)

local diffview_config
local windows = setmetatable({}, {
	__index = function(self, winid)
		local options = {
			winhl = "Normal:Normal,DiffChange:DiffviewDiffChange,DiffText:DiffviewDiffText",
		}
		rawset(self, winid, options)
		return options
	end,
})

_G.vim = {
	g = { colors_name = "github_light" },
	wo = windows,
	keymap = { set = function() end },
	cmd = function() end,
}

package.preload.gitsigns = function()
	return { setup = function() end }
end
package.preload["diffview.actions"] = function()
	return {
		conflict_choose = function()
			return function() end
		end,
		conflict_choose_all = function()
			return function() end
		end,
	}
end
package.preload.diffview = function()
	return {
		setup = function(config)
			diffview_config = config
		end,
	}
end
package.preload["which-key"] = function()
	return { add = function() end }
end

local git = dofile("lua/tw/git.lua")
git.setup()

test("layout cycle exposes unified inline diffs", function()
	eq_list({
		"diff2_horizontal",
		"diff1_inline",
		"diff2_vertical",
	}, diffview_config.view.cycle_layouts.default)
	eq("unified", diffview_config.view.inline.style)
end)

test("old side uses red changed-line highlights", function()
	diffview_config.hooks.diff_buf_win_enter(1, 10, {
		symbol = "a",
		layout_name = "diff2_horizontal",
	})
	eq("Normal:Normal,DiffChange:DiffDelete,DiffText:TwDiffviewDeleteText", windows[10].winhl)
end)

test("new side uses green changed-line highlights", function()
	diffview_config.hooks.diff_buf_win_enter(1, 11, {
		symbol = "b",
		layout_name = "diff2_horizontal",
	})
	eq("Normal:Normal,DiffChange:DiffAdd,DiffText:TwDiffviewAddText", windows[11].winhl)
end)

test("non-GitHub themes keep Diffview highlights", function()
	vim.g.colors_name = "kanagawa"
	diffview_config.hooks.diff_buf_win_enter(1, 12, {
		symbol = "a",
		layout_name = "diff2_horizontal",
	})
	eq("Normal:Normal,DiffChange:DiffviewDiffChange,DiffText:DiffviewDiffText", windows[12].winhl)
end)

H.finish("Diffview highlight tests")
