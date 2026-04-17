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
	--   Worktree commit: /abs/path/to/main-repo/.git/worktrees/<name>/<sha>/<rel-path>
	--           e.g., /Users/foo/main/.git/worktrees/feature-branch/abc1234def0/src/bar.lua
	--   Worktree stage:  /abs/path/to/main-repo/.git/worktrees/<name>/:<N>:/<rel-path>
	--           e.g., /Users/foo/main/.git/worktrees/feature-branch/:0:/src/bar.lua
	--   Null:   null (handled above)
	--
	-- Source: diffview.nvim/lua/diffview/vcs/file.lua, File:create_buffer()
	--
	-- Uses greedy (.*) match so the LAST .git/ in the path is matched,
	-- handling cases where .git appears in parent directory names.
	--
	-- Worktree patterns are tried first because they are more specific;
	-- the non-worktree commit pattern would incorrectly match worktree
	-- URIs (treating "worktrees" as a SHA).

	local repo_root, rel_path

	-- Try worktree commit pattern: .../.git/worktrees/<name>/<sha>/<rel-path>
	local main_root, wt_name, wt_rel = path:match("^(.*)/%.git/worktrees/([^/]+)/[^/]+/(.+)$")
	if not wt_rel then
		-- Try worktree stage pattern: .../.git/worktrees/<name>/:<N>:/<rel-path>
		main_root, wt_name, wt_rel = path:match("^(.*)/%.git/worktrees/([^/]+)/:%d+:/(.+)$")
	end

	if main_root and wt_name and wt_rel then
		-- Resolve the worktree's actual working directory by reading
		-- <main-repo>/.git/worktrees/<name>/gitdir which contains the
		-- path to the worktree's .git file (whose parent is the worktree root).
		local gitdir_file = main_root .. "/.git/worktrees/" .. wt_name .. "/gitdir"
		local fh = io.open(gitdir_file, "r")
		if fh then
			local gitdir_content = fh:read("*a")
			fh:close()
			gitdir_content = gitdir_content:gsub("[\n\r%s]*$", "")
			-- gitdir contains path to <worktree-root>/.git
			repo_root = gitdir_content:match("^(.+)/%.git$")
		end
		-- Fallback: if gitdir couldn't be read or parsed, use main repo root
		if not repo_root then
			repo_root = main_root
		end
		rel_path = wt_rel
	else
		-- Try regular commit rev pattern: .../<repo-root>/.git/<sha>/<rel-path>
		repo_root, rel_path = path:match("^(.*)/%.git/[^/]+/(.+)$")
		if not rel_path then
			-- Try regular stage rev pattern: .../<repo-root>/.git/:<N>:/<rel-path>
			repo_root, rel_path = path:match("^(.*)/%.git/:%d+:/(.+)$")
		end
	end

	if not repo_root or not rel_path then
		return nil, nil
	end

	return repo_root .. "/" .. rel_path, repo_root
end

function M.get_buffer_files()
	local files = {}
	local seen = {}
	local buffers = vim.api.nvim_list_bufs()
	-- Hoist git root lookup above loop — avoid per-buffer subprocess spawning
	local fallback_root = M.get_git_root()

	for _, buf in ipairs(buffers) do
		if vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			-- Resolve diffview URIs to real paths before any checks
			local resolved, repo_root = M.resolve_file_path(name)
			if resolved and not seen[resolved] then
				-- Check if resolved path exists on disk
				if vim.fn.filereadable(resolved) == 1 then
					seen[resolved] = true
					local git_root = repo_root or fallback_root
					local rel_path = Path:new(resolved):make_relative(git_root)
					table.insert(files, "@" .. rel_path)
				end
			end
		end
	end

	return files
end

return M
