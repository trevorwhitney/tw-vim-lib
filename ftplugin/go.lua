local M = {}

local function settings()
	local set = vim.opt
	set.tabstop = 2
	set.shiftwidth = 2
end

local function get_build_tags_flag()
	local tags = vim.g.go_build_tags
	if tags and tags ~= "" then
		return "-tags " .. tags .. " "
	end
	return ""
end

local function keybindings()
	local keymap = {
		{ "<leader>d", group = "Debug", nowait = false, remap = false },
		{
			"<leader>dA",
			function()
				local args = vim.fn.input({ prompt = "Args: " })
				vim.cmd("write")
				require("tw.languages.go").debug_relative({ args })
			end,
			desc = "Debug Relative (Arguments)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>dD",
			function()
				local go = require("tw.languages.go")
				local test_name = go.get_test_name()

				vim.cmd("update")
				go.debug(test_name)
			end,
			desc = "Debug (Prompt for Name)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>da",
			function()
				vim.cmd("write")
				require("tw.languages.go").debug_relative()
			end,
			desc = "Debug Relative",
			nowait = false,
			remap = false,
		},
		{
			"<leader>dd",
			function()
				local go = require("tw.languages.go")

				vim.cmd("update")
				go.debug()
			end,
			desc = "Debug",
			nowait = false,
			remap = false,
		},
		{
			"<leader>dm",
			function()
				vim.cmd("update")
				require("tw.languages.go").remote_debug(
					vim.fn.input({ prompt = "Remote Path: " }),
					vim.fn.input({ prompt = "Port: " })
				)
			end,
			desc = "Remote Debug",
			nowait = false,
			remap = false,
		},

		{ "<leader>t", group = "Test", nowait = false, remap = false },
		{
			"<leader>tT",
			function()
				local go = require("tw.languages.go")
				local package_name = "./" .. vim.fn.expand("%:h")

				local test_name = go.get_test_name()
				local cmd =
					string.format("Dispatch go test -v %s-run '%s' %s ", get_build_tags_flag(), test_name, package_name)

				vim.cmd("update")
				vim.fn.execute(cmd)
			end,
			desc = "Test (Prompt for Name)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tC",
			function()
				local go = require("tw.languages.go")
				local claude = require("tw.claude")
				local package_name = "./" .. vim.fn.expand("%:h")

				local test_name = go.get_test_name()
				local cmd = string.format("go test -v %s-run '%s' %s ", get_build_tags_flag(), test_name, package_name)

				vim.cmd("update")
				-- ":w<cr> :TestNearest -strategy=claude<cr>",
				claude.SendCommand({ cmd })
			end,
			desc = "Test with Claude (Prompt for Name)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tp",
			function()
				local package_name = "./" .. vim.fn.expand("%:h")
				local cmd = string.format("Dispatch go test -v %s%s ", get_build_tags_flag(), package_name)

				vim.cmd("update")
				vim.fn.execute(cmd)
			end,
			desc = "Package Tests",
			nowait = false,
			remap = false,
		},
		{ "<leader>c", group = "AI Code Assistant", nowait = true, remap = false },
		{
			"<leader>Tc",
			function()
				local go = require("tw.languages.go")
				local claude = require("tw.claude")
				local package_name = "./" .. vim.fn.expand("%:h")

				local test_name = go.get_test_name()
				local cmd = string.format("go test -v %s-run '%s' %s", get_build_tags_flag(), test_name, package_name)

				vim.cmd("update")
				claude.SendCommand(cmd)
			end,
			desc = "Claude Test (Prompt for Name)",
			nowait = false,
			remap = false,
		},

		{
			"<leader>gT",
			":<C-u>wincmd o<cr> :vsplit<cr> :<C-u>GoAlternate<cr>",
			desc = "Go to Alternate (In Vertical Split)",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gi",
			":<C-u>GoImpl<cr>",
			desc = "Go Implement Interface",
			nowait = false,
			remap = false,
		},
		{
			"<leader>gt",
			":<C-u>GoAlternate<cr>",
			desc = "Go to Alternate",
			nowait = false,
			remap = false,
		},

		{
			"<leader>tj",
			":GoAddTags json<cr>",
			desc = "Add JSON Tags",
			nowait = false,
			remap = false,
		},
		{
			"<leader>tx",
			":GoRemoveTags<cr>",
			desc = "Remove Tags",
			nowait = false,
			remap = false,
		},
		{
			"<leader>ty",
			":GoAddTags yaml<cr>",
			desc = "Add YAML Tags",
			nowait = false,
			remap = false,
		},
	}

	local whichkey = require("which-key")
	whichkey.add(keymap)
end

function M.setup()
	settings()
	keybindings()
end

M.setup()
