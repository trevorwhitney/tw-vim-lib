# Workspace-Mirroring Docker Mounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mount `~/workspace` into Docker containers at `/home/node/workspace` so cross-project references resolve at the same relative paths, with fallback to current behavior when CWD is outside `~/workspace`.

**Architecture:** A `workspace_mount_info()` helper in `docker/init.lua` determines whether to use the full workspace mount or the CWD-only fallback. All downstream logic (primary mount, context dirs, worktree handling, working directory, OpenCode project path) branches on this info. The Dockerfile WORKDIR is updated to `/home/node/workspace`.

**Tech Stack:** Lua (Neovim plugin), Docker

**Spec:** `docs/superpowers/specs/2026-03-26-workspace-mirroring-docker-mounts-design.md`

---

### Task 1: Update Dockerfile WORKDIR

**Files:**

- Modify: `lua/tw/agent/docker/Dockerfile:184`

- [ ] **Step 1: Change WORKDIR**

In `lua/tw/agent/docker/Dockerfile`, change line 184 from:

```dockerfile
WORKDIR /workspace
```

to:

```dockerfile
WORKDIR /home/node/workspace
```

- [ ] **Step 2: Verify Dockerfile is valid**

Run: `docker build --check -f lua/tw/agent/docker/Dockerfile lua/tw/agent/docker/ 2>&1 | head -5`

If `--check` is not supported by your docker version, just visually confirm the change looks correct.

- [ ] **Step 3: Commit**

```bash
git add lua/tw/agent/docker/Dockerfile
git commit -m "feat: update Dockerfile WORKDIR to /home/node/workspace"
```

---

### Task 2: Add `workspace_mount_info()` helper to `docker/init.lua`

This is the central helper that all other changes depend on. It determines mount strategy and container paths.

**Files:**

- Modify: `lua/tw/agent/docker/init.lua` (add new function after line 41, before `create_worktree_git_file`)

- [ ] **Step 1: Add the constants and helper function**

Add the following after the `detect_worktree()` function (after line 41) and before `create_worktree_git_file` (line 43):

```lua
-- Constants for workspace-mirroring mount strategy
local CONTAINER_HOME = "/home/node"
local CONTAINER_WORKSPACE = CONTAINER_HOME .. "/workspace"

-- Determine mount strategy based on whether CWD is under ~/workspace.
-- Returns a table with mount info:
--   host_workspace: expanded ~/workspace path (string)
--   container_workspace: "/home/node/workspace" (string)
--   is_workspace_mode: true if CWD is under ~/workspace (boolean)
--   mount_source: host path to mount (~/workspace or CWD) (string)
--   mount_target: container path to mount at (string)
--   container_cwd: the working directory inside the container (string)
function M.workspace_mount_info()
	local host_workspace = vim.fn.expand("~/workspace")
	-- Ensure no trailing slash for consistent prefix matching
	host_workspace = host_workspace:gsub("/$", "")
	local cwd = vim.fn.getcwd()

	-- Check if CWD is under ~/workspace (equal to it or a subdirectory)
	local is_workspace_mode = cwd == host_workspace or cwd:sub(1, #host_workspace + 1) == host_workspace .. "/"

	if is_workspace_mode then
		-- Derive container CWD by replacing host prefix with container prefix
		local relative = cwd:sub(#host_workspace + 1) -- includes leading "/" or is ""
		local container_cwd = CONTAINER_WORKSPACE .. relative

		return {
			host_workspace = host_workspace,
			container_workspace = CONTAINER_WORKSPACE,
			is_workspace_mode = true,
			mount_source = host_workspace,
			mount_target = CONTAINER_WORKSPACE,
			container_cwd = container_cwd,
		}
	else
		-- Fallback: mount CWD at /home/node/workspace (same as old /workspace behavior)
		return {
			host_workspace = host_workspace,
			container_workspace = CONTAINER_WORKSPACE,
			is_workspace_mode = false,
			mount_source = cwd,
			mount_target = CONTAINER_WORKSPACE,
			container_cwd = CONTAINER_WORKSPACE,
		}
	end
end
```

- [ ] **Step 2: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 3: Commit**

```bash
git add lua/tw/agent/docker/init.lua
git commit -m "feat: add workspace_mount_info() helper for mount strategy"
```

---

### Task 3: Update worktree handling to use workspace mount info

The worktree `container_gitdir` and `.git` file mount path need to change based on whether we're in workspace mode.

**Files:**

- Modify: `lua/tw/agent/docker/init.lua` — `detect_worktree()` (lines 4-41) and `create_worktree_git_file()` (lines 43-58)

- [ ] **Step 1: Update `detect_worktree()` to accept mount info**

Replace the entire `detect_worktree()` function (lines 4-41) with:

```lua
-- Detect if we're in a git worktree and return worktree info.
-- mount_info: result of workspace_mount_info(), used to determine container paths.
--   If nil, falls back to legacy /git-root based paths.
function M.detect_worktree(mount_info)
	local git_path = vim.fn.getcwd() .. "/.git"

	-- Check if .git is a file (worktree indicator)
	if vim.fn.filereadable(git_path) == 1 then
		local file = io.open(git_path, "r")
		if file then
			local content = file:read("*a")
			file:close()

			-- Parse gitdir line
			local gitdir = content:match("gitdir:%s*(.+)")
			if gitdir then
				-- Trim whitespace
				gitdir = gitdir:gsub("^%s+", ""):gsub("%s+$", "")

				-- Get the main repository path (parent of .git/worktrees)
				-- gitdir format: /path/to/repo/.git/worktrees/worktree-name
				local main_repo = gitdir:match("(.+)/%.git/worktrees/[^/]+$")

				if main_repo then
					-- Resolve to absolute path
					main_repo = vim.fn.fnamemodify(main_repo, ":p")

					-- Determine the container gitdir path based on mount strategy
					local container_gitdir
					if mount_info and mount_info.is_workspace_mode then
						-- Main repo is under ~/workspace, rewrite host prefix to container prefix
						local host_ws = mount_info.host_workspace
						container_gitdir = gitdir:gsub("^" .. vim.pesc(host_ws), mount_info.container_workspace)
					else
						-- Fallback: main repo mounted at /git-root
						container_gitdir = gitdir:gsub("^" .. vim.pesc(main_repo), "/git-root/")
					end

					-- Determine where to mount the .git file inside the container
					local container_git_mount_path
					if mount_info and mount_info.is_workspace_mode then
						container_git_mount_path = mount_info.container_cwd .. "/.git"
					else
						container_git_mount_path = CONTAINER_WORKSPACE .. "/.git"
					end

					return {
						worktree_dir = vim.fn.getcwd(),
						gitdir = gitdir,
						main_repo = main_repo,
						container_gitdir = container_gitdir,
						container_git_mount_path = container_git_mount_path,
						-- Track whether main repo needs a separate mount
						needs_git_root_mount = not (mount_info and mount_info.is_workspace_mode),
					}
				end
			end
		end
	end

	return nil
end
```

- [ ] **Step 2: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 3: Commit**

```bash
git add lua/tw/agent/docker/init.lua
git commit -m "feat: update detect_worktree() to use workspace mount info"
```

---

### Task 4: Update `get_start_container_command()` to use workspace mount

This is the core change — replacing the CWD mount with workspace mount, filtering context dirs, and updating worktree mounts.

**Files:**

- Modify: `lua/tw/agent/docker/init.lua` — `get_start_container_command()` (lines 92-213)

- [ ] **Step 1: Update the function signature and mount logic**

Replace `get_start_container_command()` entirely (lines 92-213). The new version computes mount info first and uses it throughout:

```lua
function M.get_start_container_command(container_name, context_dirs)
	container_name = container_name or "claude-code-nvim"
	context_dirs = context_dirs or {}
	local os_type = vim.uv.os_uname().sysname
	local network_flag = ""

	if os_type == "Linux" then
		network_flag = "--network host"
	end

	-- Determine mount strategy
	local mount_info = M.workspace_mount_info()

	-- Check if we're in a git worktree
	local worktree_info = M.detect_worktree(mount_info)
	local worktree_git_file = nil

	if worktree_info then
		-- Create temporary .git file with corrected paths
		worktree_git_file = M.create_worktree_git_file(worktree_info)
	end

	-- Build the docker command for persistent container
	local docker_cmd = {
		"docker",
		"run",
		"-d",
		"--name",
		container_name,
		"--cap-add",
		"NET_ADMIN",
	}

	-- Add network flag if it's not empty
	if network_flag ~= "" then
		table.insert(docker_cmd, network_flag)
	end

	-- Add context directory mounts (skip dirs already under workspace mount)
	for source_path, _ in pairs(context_dirs) do
		-- In workspace mode, skip dirs that are under ~/workspace (already accessible)
		if mount_info.is_workspace_mode then
			local host_ws = mount_info.host_workspace
			local is_under_workspace = source_path == host_ws
				or source_path:sub(1, #host_ws + 1) == host_ws .. "/"
			if is_under_workspace then
				goto continue_context
			end
		end

		local dir_name = vim.fn.fnamemodify(source_path, ":t")
		-- Ensure unique mount points by using full path hash if duplicate names
		local mount_name = dir_name
		local existing_count = 0
		for other_path, _ in pairs(context_dirs) do
			if other_path ~= source_path and vim.fn.fnamemodify(other_path, ":t") == dir_name then
				existing_count = existing_count + 1
			end
		end
		if existing_count > 0 then
			-- Add a hash suffix for uniqueness
			local hash = vim.fn.sha256(source_path)
			mount_name = dir_name .. "_" .. string.sub(hash, 1, 8)
		end
		table.insert(docker_cmd, "-v")
		table.insert(docker_cmd, source_path .. ":/context/" .. mount_name)

		::continue_context::
	end

	-- Add worktree-specific mounts if needed
	if worktree_info and worktree_git_file then
		-- Only mount the main repo at /git-root if NOT in workspace mode
		if worktree_info.needs_git_root_mount then
			table.insert(docker_cmd, "-v")
			table.insert(docker_cmd, worktree_info.main_repo .. ":/git-root")
		end

		-- Mount the corrected .git file at the appropriate container path
		table.insert(docker_cmd, "-v")
		table.insert(docker_cmd, worktree_git_file .. ":" .. worktree_info.container_git_mount_path .. ":ro")
	end

	-- Add the primary workspace mount
	-- Add the rest of the arguments
	local remaining_args = {
		"-v",
		mount_info.mount_source .. ":" .. mount_info.mount_target,
		"-v",
		vim.fn.expand("~/.config/claude-container") .. ":/home/node/.claude",
		"-v",
		vim.fn.expand("~/.config/gemini-container") .. ":/home/node/.gemini",
		"-v",
		vim.fn.expand("~/.config/codex-container") .. ":/home/node/.codex",
		"-v",
		"claude-history:/commandhistory",
		"-v",
		vim.fn.expand("~/.config/git") .. ":/home/node/.config/git:ro",
		"-v",
		vim.fn.expand("~/.ssh") .. ":/home/node/.ssh:ro",
		"-e",
		"NODE_OPTIONS=--max-old-space-size=4096",
		"-e",
		"CLAUDE_CONFIG_DIR=/home/node/.claude",
		"-e",
		"ANTHROPIC_API_KEY=" .. (vim.env.ANTHROPIC_API_KEY or ""),
		"-e",
		"GITHUB_PERSONAL_ACCESS_TOKEN=" .. (vim.env.GITHUB_PERSONAL_ACCESS_TOKEN or ""),
		"-e",
		"GH_TOKEN=" .. (vim.env.GH_TOKEN or ""),
		"-e",
		"OPENAI_API_KEY=" .. (vim.env.OPENAI_API_KEY or ""),
		"-e",
		"COLORTERM=" .. (vim.env.COLORTERM or "truecolor"),
		"-e",
		"FORCE_COLOR=1",
		"-e",
		"EDITOR=vim",
		"-e",
		"CLAUDE_INBOX_URL=" .. (vim.env.CLAUDE_INBOX_URL or "http://host.docker.internal:43111/events"),
	}

	-- Add remaining arguments to docker command
	for _, arg in ipairs(remaining_args) do
		table.insert(docker_cmd, arg)
	end

	-- Add the container image and command
	local final_args = {
		"tw-claude-code:latest",
		"tail",
		"-f",
		"/dev/null",
	}
	for _, arg in ipairs(final_args) do
		table.insert(docker_cmd, arg)
	end

	return table.concat(docker_cmd, " "), mount_info
end
```

Note: the function now returns `mount_info` as a second return value so callers can use it for working directory and project path computation.

- [ ] **Step 2: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 3: Commit**

```bash
git add lua/tw/agent/docker/init.lua
git commit -m "feat: update get_start_container_command() with workspace mount logic"
```

---

### Task 5: Update `attach_to_container()` with working directory support

**Files:**

- Modify: `lua/tw/agent/docker/init.lua` — `attach_to_container()` (lines 215-234)

- [ ] **Step 1: Add `working_dir` parameter**

Replace `attach_to_container()` (lines 215-234) with:

```lua
function M.attach_to_container(container_name, args, command, working_dir)
	container_name = container_name or "claude-code-nvim"
	args = args or ""
	command = command or "claude"
	working_dir = working_dir or CONTAINER_WORKSPACE
	if args ~= "" then
		args = " " .. args
	end

	local cmd_string
	if command == "codex" then
		cmd_string = "codex --search --full-auto" .. args
	elseif command == "opencode" then
		cmd_string = "opencode" .. args
	else
		cmd_string = "claude --dangerously-skip-permissions" .. args
	end

	local cmd = "docker exec -it -w " .. working_dir .. " " .. container_name .. ' /bin/bash -c "' .. cmd_string .. '"'
	return cmd
end
```

- [ ] **Step 2: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 3: Commit**

```bash
git add lua/tw/agent/docker/init.lua
git commit -m "feat: add working_dir parameter to attach_to_container()"
```

---

### Task 6: Update `init.lua` to pass mount info through and fix OpenCode project path

This task updates `start_new_agent_job()` in `lua/tw/agent/init.lua` to:
1. Capture `mount_info` from the container start command
2. Pass `working_dir` to `attach_to_container()`
3. Compute the OpenCode project path using workspace mount info instead of context dirs

**Files:**

- Modify: `lua/tw/agent/init.lua` — `start_new_agent_job()` (lines 151-351)

- [ ] **Step 1: Store mount_info on the module**

Add a field to store mount info after the `context_directories` line (around line 49). After:

```lua
M.context_directories = {} -- Table of paths to mount at /context/*
```

Add:

```lua
M.mount_info = nil -- Cached workspace mount info from last container start
```

- [ ] **Step 2: Update `start_container_after_build()` call chain to capture mount_info**

In `lua/tw/agent/docker/init.lua`, the `start_container_after_build()` function calls `get_start_container_command()` at line 496. Update that line to capture the mount info:

```lua
local start_cmd, mount_info = M.get_start_container_command(container_name, context_directories)
```

Then pass `mount_info` through the callback. Update the callback at line 537 (the `callback(true, "running")` call) to also pass mount_info:

```lua
callback(true, "running", mount_info)
```

Also update all other callback calls in the function to pass `nil` for mount_info (lines where `callback(false, ...)` is called):
- Line 549: `callback(false, "not_running")` — no change needed (nil is implicit)
- Line 558: `callback(false, "start_failed")` — no change needed

- [ ] **Step 3: Update `start_container_async()` to pass mount_info through**

In `lua/tw/agent/docker/init.lua`, `start_container_async()` calls `start_container_after_build()` which calls back with mount_info. The callback chain flows through to `init.lua`. No change needed in `start_container_async()` itself — the callback signature just gains an optional third argument.

- [ ] **Step 4: Capture mount_info in `wait_for_container_start()` in `init.lua`**

In `lua/tw/agent/init.lua`, update `wait_for_container_start()` (around line 227) to capture mount_info from the callback.

Replace the `wait_for_container_start` local function (lines 227-271) with:

```lua
			local function wait_for_container_start(action_name)
				local success_flag = false
				local captured_mount_info = nil
				docker.start_container_async(
					M.container_name,
					M.auto_build,
					M.context_directories,
					function(success, status, mount_info)
						if success then
							M.container_started = true
							captured_mount_info = mount_info
							success_flag = true
						else
							log.error(
								"Failed to " .. action_name .. " container: " .. (status or "Unknown error"),
								true
							)
							M.container_started = false
							success_flag = false
						end
					end
				)

				-- Wait for container with timeout
				local timeout = 30000 -- 30 seconds
				local check_interval = 500 -- 0.5 seconds
				local elapsed = 0
				while elapsed < timeout do
					vim.wait(check_interval)
					elapsed = elapsed + check_interval
					if success_flag then
						break
					end
					if not success_flag and elapsed >= timeout then
						log.error("Container " .. action_name .. " timed out", true)
						M.container_started = false
						return false
					end
				end

				if not success_flag then
					log.error("Container " .. action_name .. " failed", true)
					M.container_started = false
					return false
				end
				M.mount_info = captured_mount_info
				return true
			end
```

- [ ] **Step 5: Update OpenCode project path logic for workspace mode**

Replace the OpenCode docker project path block (lines 171-193) with:

```lua
			if is_docker then
				-- Determine project path based on mount strategy
				local mi = docker.workspace_mount_info()
				if mi.is_workspace_mode then
					-- Git root is accessible under the workspace mount — translate path directly
					local host_ws = mi.host_workspace
					local is_git_root_under_ws = git_root == host_ws
						or git_root:sub(1, #host_ws + 1) == host_ws .. "/"
					if is_git_root_under_ws then
						local relative = git_root:sub(#host_ws + 1) -- includes leading "/"
						project_path = mi.container_workspace .. relative
					else
						-- Git root outside workspace — fall back to context dir mount
						if not M.context_directories[git_root] then
							M.context_directories[git_root] = true
							log.info("Auto-added git root to context directories: " .. git_root)
						end
						local dir_name = vim.fn.fnamemodify(git_root, ":t")
						project_path = "/context/" .. dir_name
					end
				else
					-- Fallback mode: git root IS the mounted CWD
					project_path = mi.container_workspace
				end
				log.debug("Docker project path: " .. project_path)
```

- [ ] **Step 6: Update `attach_to_container` call to pass working_dir**

In `start_new_agent_job()`, around line 293, the attach call is:

```lua
		command = docker.attach_to_container(M.container_name, cmd_args, command_name)
```

Replace with:

```lua
		-- Use mount info for working directory (may have been set during container start,
		-- or compute fresh if container was already running)
		local working_dir
		if M.mount_info then
			working_dir = M.mount_info.container_cwd
		else
			working_dir = docker.workspace_mount_info().container_cwd
		end
		command = docker.attach_to_container(M.container_name, cmd_args, command_name, working_dir)
```

- [ ] **Step 7: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 8: Commit**

```bash
git add lua/tw/agent/docker/init.lua lua/tw/agent/init.lua
git commit -m "feat: wire workspace mount info through container start and agent attach"
```

---

### Task 7: Fix stale Dockerfile path references

The Makefile and `get_plugin_root()` in `docker/init.lua` reference the old `lua/tw/claude/docker/` path. Fix them to use the current `lua/tw/agent/docker/` path.

**Files:**

- Modify: `Makefile:14-15`
- Modify: `lua/tw/agent/docker/init.lua` — `get_plugin_root()` (lines 61-66) and `build_docker_image()` (lines 68-72)

- [ ] **Step 1: Fix Makefile**

In `Makefile`, replace line 15:

```makefile
	docker build -t tw-claude-code:latest -f lua/tw/claude/docker/Dockerfile lua/tw/claude/docker
```

with:

```makefile
	docker build -t tw-claude-code:latest -f lua/tw/agent/docker/Dockerfile lua/tw/agent/docker
```

- [ ] **Step 2: Fix `get_plugin_root()` in `docker/init.lua`**

Replace lines 61-66:

```lua
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/claude/docker/init%.lua$")
	return plugin_root
end
```

with:

```lua
local function get_plugin_root()
	local source = debug.getinfo(1, "S").source
	local file_path = string.sub(source, 2) -- Remove the '@' prefix
	local plugin_root = string.match(file_path, "(.-)/lua/tw/agent/docker/init%.lua$")
	return plugin_root
end
```

- [ ] **Step 3: Fix `build_docker_image()`**

Replace lines 68-72:

```lua
function M.build_docker_image()
	local plugin_root = get_plugin_root()
	local docker_dir = plugin_root .. "/lua/tw/claude/docker"
	return "cd " .. docker_dir .. " && docker build -t tw-claude-code:latest ."
end
```

with:

```lua
function M.build_docker_image()
	local plugin_root = get_plugin_root()
	local docker_dir = plugin_root .. "/lua/tw/agent/docker"
	return "cd " .. docker_dir .. " && docker build -t tw-claude-code:latest ."
end
```

- [ ] **Step 4: Verify no syntax errors**

Run: `make lint-lua 2>&1 | grep -i error || echo "No errors"`

- [ ] **Step 5: Commit**

```bash
git add Makefile lua/tw/agent/docker/init.lua
git commit -m "fix: update stale lua/tw/claude/docker references to lua/tw/agent/docker"
```

---

### Task 8: Run full lint and format

**Files:** All modified files

- [ ] **Step 1: Format**

Run: `make format`

- [ ] **Step 2: Lint**

Run: `make lint`

Fix any issues found.

- [ ] **Step 3: Commit if formatting changed anything**

```bash
git add -A
git diff --cached --quiet || git commit -m "chore: format after workspace mount changes"
```

---

### Task 9: Manual smoke test

This is a manual verification task. The implementer should perform these checks if they have access to the Neovim environment.

- [ ] **Step 1: Test workspace mode**

1. Open Neovim in `~/workspace/some-project`
2. Run `:AiAgent opencode-docker` (or the equivalent toggle keymap `<leader>cO`)
3. Inside the container, verify:
   - `pwd` shows `/home/node/workspace/some-project`
   - `ls /home/node/workspace/` shows other projects from your host `~/workspace/`
   - `ls ../other-project` works for a sibling project

- [ ] **Step 2: Test fallback mode**

1. Open Neovim in `/tmp/test-project`
2. Launch a docker agent
3. Verify `pwd` shows `/home/node/workspace` and the project files are there

- [ ] **Step 3: Test worktree**

1. Open Neovim in a git worktree under `~/workspace/project/worktree-1`
2. Launch a docker agent
3. Inside the container, run `git status` — it should work correctly
4. Verify there is no `/git-root` mount (`ls /git-root` should fail)

- [ ] **Step 4: Test context dir filtering**

1. Open Neovim in `~/workspace/project-a`
2. Run `:AiAgent add-context ~/workspace/project-b`
3. Launch a docker agent
4. Verify `/context/project-b` does NOT exist (it's already under the workspace mount)
5. Run `:AiAgent add-context /opt/external-lib`
6. Restart the docker agent
7. Verify `/context/external-lib` DOES exist
