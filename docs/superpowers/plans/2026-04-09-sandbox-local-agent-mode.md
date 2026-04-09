# Sandbox Local Agent Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unsandboxed local agent execution with sandbox-wrapped execution via `~/.config/sandbox-exec/run-sandboxed.sh`, and fix broken Docker `add-context`/`remove-context` restart logic.

**Architecture:** Modify `claude.lua:command()` to prepend the sandbox wrapper and per-agent permission flags. Simplify `init.lua`'s local branch to delegate flag logic to `claude.lua`. Add `M.restart_local_agent()` public helper to `init.lua`. Refactor `commands.lua` `add-context`/`remove-context` handlers to dispatch restarts for both Docker and local modes via a shared helper.

**Tech Stack:** Lua (Neovim plugin), `vim.fn.termopen()`, `io.popen`, macOS `sandbox-exec`

**Spec:** `docs/superpowers/specs/2026-04-09-sandbox-local-agent-mode-design.md`

---

### Task 1: Rewrite `claude.lua` and simplify `init.lua` local branch

**Files:**

- Modify: `lua/tw/agent/claude.lua` (entire file — 51 lines)
- Modify: `lua/tw/agent/init.lua:306-321` (local branch in `start_new_agent_job`)

- [ ] **Step 1: Rewrite `claude.lua` with sandbox wrapping and per-agent flags**

Replace the entire file with:

```lua
local M = {}

local SANDBOX_WRAPPER = vim.fn.expand("~/.config/sandbox-exec/run-sandboxed.sh")
local sandbox_available = vim.fn.executable(SANDBOX_WRAPPER) == 1
local sandbox_warned = false

-- Per-agent permission flags (unconditional — applied with and without sandbox)
local AGENT_FLAGS = {
    claude = { "--dangerously-skip-permissions" },
    codex = { "--full-auto" },
    -- opencode: no flags needed
}

local get_command_path = function(command_name)
    local handle = io.popen(table.concat({ "command", "-v", command_name }, " "))
    local command_path = ""
    if handle then
        local result = handle:read("*a")
        if result then
            command_path = result:gsub("\n", "")
        end
        handle:close()
    end

    return command_path
end

-- Build command for any AI coding assistant (claude, codex, opencode)
-- context_directories: table of {[abs_path] = true} for sandbox --add-dirs
function M.command(args, command_name, context_directories)
    command_name = command_name or "claude"
    local command_path = get_command_path(command_name)
    if command_path == "" then
        vim.api.nvim_err_writeln(command_name .. " executable not found in PATH")
        return
    end

    if type(args) == "string" then
        args = { args }
    elseif type(args) ~= "table" then
        args = {}
    end

    local command = {}

    -- Sandbox wrapper (if available)
    if sandbox_available then
        table.insert(command, SANDBOX_WRAPPER)

        -- --add-dirs for context directories (sorted for determinism)
        if context_directories and not vim.tbl_isempty(context_directories) then
            local dirs = vim.tbl_keys(context_directories)
            table.sort(dirs)
            table.insert(command, "--add-dirs=" .. table.concat(dirs, ":"))
        end
    else
        if not sandbox_warned then
            vim.notify(
                "Sandbox wrapper not found: " .. SANDBOX_WRAPPER .. " — running agent without sandbox",
                vim.log.levels.WARN
            )
            sandbox_warned = true
        end
    end

    -- Agent binary
    table.insert(command, command_path)

    -- Per-agent permission flags (unconditional)
    local flags = AGENT_FLAGS[command_name]
    if flags then
        for _, flag in ipairs(flags) do
            table.insert(command, flag)
        end
    end

    -- Caller-provided args
    for _, arg in ipairs(args) do
        table.insert(command, arg)
    end

    return table.concat(command, " ")
end

return M
```

Key changes from current code:
- Added sandbox wrapper detection and `AGENT_FLAGS` table at module level
- `command()` takes new `context_directories` parameter
- Sandbox wrapper + `--add-dirs` prepended when available
- Per-agent flags applied unconditionally (replaces `init.lua`'s `--dangerously-skip-permissions`)
- Removed `CLAUDE_CONFIG_DIR` env var prefix (sandbox profile grants `~/.config` read access; assumes standard `XDG_CONFIG_HOME`)

- [ ] **Step 2: Simplify `init.lua` local branch**

In `lua/tw/agent/init.lua`, replace lines 306-321 (the `else` branch in `start_new_agent_job`):

Old code:
```lua
	else
		log.debug("Local mode enabled for " .. command_name)
		-- For local mode, skip permissions for all agents
		local final_args = vim.tbl_extend("force", {}, default_args)
		if command_name ~= "opencode" then
			table.insert(final_args, "--dangerously-skip-permissions")
			log.debug("Added --dangerously-skip-permissions for " .. command_name)
		end
		if args and #args > 0 then
			log.debug("Extending final_args with " .. #args .. " args")
			vim.list_extend(final_args, args)
		end
		log.debug("Final args before command: " .. vim.inspect(final_args))
		command = claude.command(final_args, command_name)
		log.debug("Using native command: " .. command)
	end
```

New code:
```lua
	else
		log.debug("Local mode enabled for " .. command_name)
		local final_args = vim.tbl_extend("force", {}, default_args)
		if args and #args > 0 then
			log.debug("Extending final_args with " .. #args .. " args")
			vim.list_extend(final_args, args)
		end
		log.debug("Final args before command: " .. vim.inspect(final_args))
		command = claude.command(final_args, command_name, M.context_directories)
		if not command then
			log.error("Failed to build command for " .. command_name, true)
			return
		end
		log.debug("Using native command: " .. command)
	end
```

Changes: removed `--dangerously-skip-permissions` insertion, passed `M.context_directories`, added nil guard.

- [ ] **Step 3: Run lint**

Run: `make lint-lua`
Expected: No errors in `lua/tw/agent/claude.lua` or `lua/tw/agent/init.lua`

- [ ] **Step 4: Commit**

```bash
git add lua/tw/agent/claude.lua lua/tw/agent/init.lua
git commit -m "feat(agent): add sandbox wrapping to local agent commands

Wrap local agent commands in ~/.config/sandbox-exec/run-sandboxed.sh
with per-agent permission flags (claude: --dangerously-skip-permissions,
codex: --full-auto). Falls back to direct execution if wrapper absent.
Pass context_directories to command builder for --add-dirs support.
Remove CLAUDE_CONFIG_DIR env var (assumes standard XDG_CONFIG_HOME)."
```

---

### Task 2: Add `M.restart_local_agent()` and refactor `commands.lua` context handlers

**Files:**

- Modify: `lua/tw/agent/init.lua` — add new public method after `M.Open()` (after line 479)
- Modify: `lua/tw/agent/commands.lua:292-395` (add-context, remove-context handlers)

- [ ] **Step 1: Add `M.restart_local_agent()` after `M.Open()` in `init.lua`**

Insert after the closing `end` of `M.Open` (line 479):

```lua
-- Restart the active local (sandboxed) agent with updated context_directories.
-- Used by add-context/remove-context. Returns true if restarted, false if no
-- local agent was running. Args are not preserved on restart — git root is
-- re-derived in start_new_agent_job().
function M.restart_local_agent()
	-- Find a running local-mode job by scanning mode-specific fields.
	-- We can't rely on active_mode because hiding a terminal sets it to "none"
	-- while the job keeps running.
	local local_modes = { "claude", "codex", "opencode" }
	local running_mode = nil
	for _, mode in ipairs(local_modes) do
		local vars = get_mode_vars(mode)
		local job_id = M[vars.job_key]
		if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			running_mode = mode
			break
		end
	end

	if not running_mode then
		return false
	end

	local vars = get_mode_vars(running_mode)
	local buf = M[vars.buf_key]
	local job_id = M[vars.job_key]
	if buf then
		terminal.close_terminal_buffer(buf, job_id)
	end
	M[vars.buf_key] = nil
	M[vars.job_key] = nil
	if M.active_mode == running_mode then
		M.active_buf = nil
		M.active_job_id = nil
		M.active_mode = "none"
	end
	M.Open(running_mode)
	return true
end
```

Key design decisions:
- Scans all local mode `*_job_id` fields via `jobwait` to find a running job, rather than relying on `active_mode` (which is `"none"` when hidden)
- Clears mode-specific fields (`opencode_buf`, etc.) not just active pointers
- Only clears `active_*` if this was the active mode (avoids clobbering another visible mode)

- [ ] **Step 2: Add `restart_agent_with_context` helper to `commands.lua`**

Insert before the `-- Add context directory` comment (before line 292):

```lua
-- Restart agent after context directory change (used by add-context and remove-context).
-- Handles both Docker and local/sandbox modes.
local function restart_agent_with_context(agent_module, action_desc)
	local mode = agent_module.active_mode

	-- Docker mode: close all docker terminal buffers, then restart container
	if mode:match("-docker$") or agent_module.container_started then
		if not agent_module.container_started then
			vim.notify(action_desc .. " — context will be applied when container starts", vim.log.levels.INFO)
			return
		end
		vim.notify("Restarting container — " .. action_desc)
		-- Close all docker buffer variants (matches handle_restart cleanup logic)
		local docker_modes = { "claude-docker", "codex-docker", "opencode-docker" }
		for _, dmode in ipairs(docker_modes) do
			local var_name = dmode:gsub("-", "_")
			local buf_key = var_name .. "_buf"
			local job_key = var_name .. "_job_id"
			if agent_module[buf_key] then
				terminal.close_terminal_buffer(agent_module[buf_key], agent_module[job_key])
				agent_module[buf_key] = nil
				agent_module[job_key] = nil
			end
		end
		agent_module.active_buf = nil
		agent_module.active_job_id = nil
		agent_module.active_mode = "none"
		docker.stop_container(agent_module.container_name)
		agent_module.container_started = false
		docker.start_container_async(
			agent_module.container_name,
			agent_module.auto_build,
			agent_module.context_directories,
			function(success)
				if success then
					agent_module.container_started = true
				end
			end
		)
		return
	end

	-- Local/sandbox mode: restart via public helper
	local restarted = agent_module.restart_local_agent()
	if restarted then
		vim.notify("Restarting agent — " .. action_desc)
	else
		vim.notify(action_desc .. " — context will be applied when agent starts", vim.log.levels.INFO)
	end
end

```

Key design decisions:
- Docker path iterates all three docker mode buffers (matching `handle_restart` at commands.lua:257-272), not just `active_buf`
- Docker path checks `container_started` for the "no container running" case
- Local path delegates to `M.restart_local_agent()` which scans for running jobs

- [ ] **Step 3: Replace `handle_add_context` with simplified version**

Replace the current `handle_add_context` function (lines 293-345) with:

```lua
local function handle_add_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :AiAgent add-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	if vim.fn.isdirectory(dir_path) == 0 then
		vim.notify("Directory does not exist: " .. dir_path, vim.log.levels.ERROR)
		return
	end
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h")
	if claude_module.context_directories[abs_path] then
		vim.notify("Context already added: " .. abs_path, vim.log.levels.INFO)
		return
	end
	claude_module.context_directories[abs_path] = true
	log.info("Added context directory: " .. abs_path)
	restart_agent_with_context(claude_module, "added context: " .. abs_path)
end
```

- [ ] **Step 4: Replace `handle_remove_context` with simplified version**

Replace the current `handle_remove_context` function (lines 348-395, adjusted for prior edits — search for `handle_remove_context`) with:

```lua
local function handle_remove_context(claude_module, args)
	local dir_path = args[1]
	if not dir_path then
		vim.notify("Usage: :AiAgent remove-context <directory>", vim.log.levels.ERROR)
		return
	end
	dir_path = vim.fn.expand(dir_path)
	local abs_path = vim.fn.fnamemodify(dir_path, ":p:h")
	if not claude_module.context_directories[abs_path] then
		vim.notify("Context not found: " .. abs_path, vim.log.levels.WARN)
		return
	end
	claude_module.context_directories[abs_path] = nil
	log.info("Removed context directory: " .. abs_path)
	restart_agent_with_context(claude_module, "removed context: " .. abs_path)
end
```

- [ ] **Step 5: Run lint**

Run: `make lint-lua`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add lua/tw/agent/init.lua lua/tw/agent/commands.lua
git commit -m "feat(agent): add local-mode context restart and fix Docker add/remove-context

Add restart_local_agent() that scans mode-specific job fields to find
running local agents (handles hidden-but-running case). Add shared
restart_agent_with_context() helper in commands.lua that dispatches
Docker or local restarts. Docker path now correctly clears all docker
mode buffer fields (fixes dead docker_buf references from prior refactor)."
```

---

### Task 3: End-to-end verification

**Files:** None (testing only)

- [ ] **Step 1: Run full lint**

Run: `make lint`
Expected: No errors across all Lua and Nix files.

- [ ] **Step 2: Verify sandbox command construction in Neovim**

Open Neovim and run:
```vim
:lua print(require("tw.agent.claude").command({"/tmp/test"}, "claude", {["/Users/twhitney/workspace/loki"] = true}))
```

Expected (substitute your paths): sandbox wrapper + `--add-dirs=/Users/twhitney/workspace/loki` + claude binary + `--dangerously-skip-permissions` + `/tmp/test`

- [ ] **Step 3: Verify per-agent flags**

```vim
:lua print(require("tw.agent.claude").command({}, "codex", {}))
```
Expected: sandbox wrapper + codex binary + `--full-auto`

```vim
:lua print(require("tw.agent.claude").command({}, "opencode", {}))
```
Expected: sandbox wrapper + opencode binary (no permission flag)

- [ ] **Step 4: Verify fallback when sandbox wrapper absent**

Temporarily rename the wrapper:
```bash
mv ~/.config/sandbox-exec/run-sandboxed.sh ~/.config/sandbox-exec/run-sandboxed.sh.bak
```

Restart Neovim, open an agent. Verify: one-time WARN notification about missing wrapper, agent runs with direct binary. Restore the wrapper:
```bash
mv ~/.config/sandbox-exec/run-sandboxed.sh.bak ~/.config/sandbox-exec/run-sandboxed.sh
```

- [ ] **Step 5: Verify `add-context` in local mode**

1. Open an agent: `<leader>co` (opencode)
2. Run `:AiAgent add-context /Users/twhitney/workspace/loki`
3. Verify: old terminal closes, new one opens
4. Run `:AiAgent list-contexts`
5. Verify: context directory is listed

- [ ] **Step 6: Verify `add-context` with hidden agent**

1. Open an agent: `<leader>co` (opencode)
2. Hide it: `<leader>co` (toggles off — sets active_mode to "none")
3. Run `:AiAgent add-context /Users/twhitney/workspace/loki`
4. Verify: agent restarts (not "will be applied when agent starts")

- [ ] **Step 7: Verify `remove-context`**

1. Run `:AiAgent remove-context /Users/twhitney/workspace/loki`
2. Verify: agent restarts without `--add-dirs`
3. Run `:AiAgent list-contexts`
4. Verify: empty

- [ ] **Step 8: Verify deferred context (no running agent)**

1. Close all agent buffers completely (`:bd!` or exit and reopen Neovim)
2. Run `:AiAgent add-context /Users/twhitney/workspace/loki`
3. Verify: notification says "context will be applied when agent starts"
4. Open agent: `<leader>co`
5. Verify: agent command includes `--add-dirs=`
