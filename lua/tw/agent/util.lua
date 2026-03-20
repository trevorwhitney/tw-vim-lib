local Path = require("plenary.path")

local M = {}

-- adapted from https://github.com/greggh/claude-code.nvim/blob/main/lua/claude-code/git.lua
function M.get_git_root()
	-- Check if we're in a git repository
	local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
	if not handle then
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	-- Strip trailing whitespace and newlines for reliable matching
	result = result:gsub("[\n\r%s]*$", "")

	if result == "true" then
		-- Get the git root path
		local root_handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
		if not root_handle then
			return nil
		end

		local git_root = root_handle:read("*a")
		root_handle:close()

		-- Remove trailing whitespace and newlines
		git_root = git_root:gsub("[\n\r%s]*$", "")

		return git_root
	end

	return nil
end

--- Resolve a buffer name to a real, absolute file path.
--- Handles diffview:// URIs by extracting the file path and resolving it
--- against the repo root embedded in the URI.
---
--- Contract: always returns (absolute_path, repo_root) or (nil, nil).
--- Never returns a relative path, empty string, or diffview:// URI.
---
--- This function is side-effect free — no vim.notify, no writes.
---
--- @param bufname string|nil Buffer name (defaults to vim.fn.expand("%"))
--- @return string|nil resolved_path Absolute file path, or nil if unresolvable
--- @return string|nil repo_root Git repo root, or nil (callers fall back to get_git_root())
function M.resolve_file_path(bufname)
	bufname = bufname or vim.fn.expand("%")

	-- Empty or nil buffer name is unresolvable
	if not bufname or bufname == "" then
		return nil, nil
	end

	-- Not a diffview buffer — return as-is (already absolute from expand("%"))
	if not bufname:match("^diffview://") then
		return bufname, nil
	end

	-- Null buffer — no file to reference
	if bufname == "diffview://null" then
		return nil, nil
	end

	-- Strip the diffview:// prefix
	local path = bufname:gsub("^diffview://", "")

	-- Extract repo root and relative file path from URI.
	--
	-- Known diffview URI formats (after stripping diffview://):
	--   Commit: /abs/path/to/repo/.git/<sha-abbrev>/<rel-path>
	--           e.g., /Users/foo/project/.git/abc1234def0/src/bar.lua
	--   Stage:  /abs/path/to/repo/.git/:<N>:/<rel-path>
	--           e.g., /Users/foo/project/.git/:0:/src/bar.lua
	--   Null:   null (handled above)
	--
	-- Source: diffview.nvim/lua/diffview/vcs/file.lua, File:create_buffer()
	--
	-- Uses greedy (.*) match so the LAST .git/ in the path is matched,
	-- handling cases where .git appears in parent directory names.

	-- Try commit rev pattern: .../<repo-root>/.git/<sha>/<rel-path>
	local repo_root, rel_path = path:match("^(.*)/%.git/[^/]+/(.+)$")
	if not rel_path then
		-- Try stage rev pattern: .../<repo-root>/.git/:<N>:/<rel-path>
		repo_root, rel_path = path:match("^(.*)/%.git/:%d+:/(.+)$")
	end

	if not repo_root or not rel_path then
		return nil, nil
	end

	return repo_root .. "/" .. rel_path, repo_root
end

function M.get_buffer_files()
	local files = {}
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		-- Include all buffers that are listed (which includes bufferline tabs)
		if vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			-- Check if buffer has a valid file path and exists on disk
			if name ~= "" and vim.fn.filereadable(name) == 1 then
				local rel_path = Path:new(name):make_relative(M.get_git_root())
				table.insert(files, "@" .. rel_path)
			end
		end
	end

	return files
end

return M
