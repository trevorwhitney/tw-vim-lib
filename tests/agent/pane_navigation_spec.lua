describe("agent pane navigation", function()
	local agent, editor, panes, original_edgy

	before_each(function()
		agent = require("tests.agent.spec_helpers").reset_and_mock()
		original_edgy = package.loaded["edgy"]
		vim.cmd("enew | only")
		editor = vim.api.nvim_get_current_win()
		panes = {}
		vim.cmd("vnew")
		vim.cmd("wincmd L")
		for idx = 0, 2 do
			if idx > 0 then
				vim.cmd("belowright new")
			end
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_buf_set_name(0, "agent://codex#" .. idx)
			vim.bo.filetype = "AgentConsole"
			local pane = { win = win, visible = true }
			function pane:hide()
				self.visible = false
				vim.api.nvim_set_current_win(editor)
			end
			panes[#panes + 1] = pane
		end
		package.loaded["edgy"] = {
			get_win = function(win)
				for _, pane in ipairs(panes) do
					if pane.win == win then
						return pane
					end
				end
			end,
			close = function()
				for _, pane in ipairs(panes) do
					if vim.api.nvim_win_is_valid(pane.win) then
						vim.api.nvim_win_close(pane.win, true)
					end
				end
			end,
		}
	end)

	after_each(function()
		package.loaded["edgy"] = original_edgy
		vim.cmd("enew | only")
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf):match("agent://") then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end)

	it("collapses to the next expanded pane, skipping collapsed panes", function()
		panes[2].visible = false
		vim.api.nvim_set_current_win(panes[1].win)
		agent.CollapsePane(panes[1])
		assert.equals(panes[3].win, vim.api.nvim_get_current_win())
		assert.is_false(panes[1].visible)
	end)

	it("wraps from the last pane to the first expanded pane", function()
		vim.api.nvim_set_current_win(panes[3].win)
		agent.CollapsePane(panes[3])
		assert.equals(panes[1].win, vim.api.nvim_get_current_win())
	end)

	it("closes the drawer when the last expanded pane collapses", function()
		panes[1].visible, panes[2].visible = false, false
		agent.CollapsePane(panes[3])
		assert.equals(editor, vim.api.nvim_get_current_win())
		for _, pane in ipairs(panes) do
			assert.is_false(vim.api.nvim_win_is_valid(pane.win))
		end
	end)

	it("enters the first expanded pane without entering a collapsed top pane", function()
		panes[1].visible = false
		vim.api.nvim_set_current_win(editor)
		local entered = {}
		local autocmd = vim.api.nvim_create_autocmd("WinEnter", {
			callback = function()
				entered[#entered + 1] = vim.api.nvim_get_current_win()
			end,
		})
		assert.is_true(agent.FocusAgentOnRight())
		vim.api.nvim_del_autocmd(autocmd)
		assert.same({ panes[2].win }, entered)
		assert.is_false(panes[1].visible)
	end)

	it("leaves navigation between editor splits to the normal mapping", function()
		vim.api.nvim_set_current_win(editor)
		vim.cmd("leftabove vnew")
		assert.is_false(agent.FocusAgentOnRight())
	end)
end)
