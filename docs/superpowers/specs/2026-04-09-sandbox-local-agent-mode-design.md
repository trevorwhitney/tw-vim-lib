# Sandbox Local Agent Mode

## Problem

The `:AiAgent` command system has two execution modes: local (raw binary) and Docker (containerized). Local mode runs agent CLIs directly with no isolation — the agent has full access to the filesystem. Docker mode provides isolation but adds overhead (image builds, container lifecycle, firewall setup) and doesn't work well on macOS where Docker Desktop performance is poor.

A macOS sandbox wrapper (`~/.config/sandbox-exec/run-sandboxed.sh`) exists that sandboxes agent CLIs with a deny-by-default policy. It provides filesystem isolation comparable to Docker with none of the overhead. The agent module needs to use this wrapper for all local agent invocations.

## Goal

Replace the unsandboxed local execution path with sandboxed execution via `run-sandboxed.sh`. When the sandbox wrapper is available, all local agent commands are wrapped through it. If the wrapper is absent (e.g., on a machine without the sandbox installed), local mode falls back to direct execution with a one-time warning — per-agent permission flags still apply in fallback mode. The `add-context` subcommand grants write access to additional directories by passing `--add-dirs` to the wrapper and restarting the agent. Docker mode is unchanged except for bug fixes to the `add-context`/`remove-context` restart path and refinement of Docker-only subcommand guards.

## Design

All files referenced in this spec live under `lua/tw/agent/`. When this spec says `claude.lua`, it means `lua/tw/agent/claude.lua`, etc.

### Sandbox Wrapper Contract

The wrapper lives at `~/.config/sandbox-exec/run-sandboxed.sh` (hardcoded, not configurable). It accepts:

```
run-sandboxed.sh [--add-dirs=<p1:p2:...>] <command> [args...]
```

- `--add-dirs`: colon-separated paths granted read/write access. Paths are passed as-is; colon characters in directory paths are not supported (and are not expected in macOS workspace paths).
- `<command>`: the agent binary path, followed by its arguments
- No `--` separator needed between wrapper flags and the command

The wrapper also supports `--workdir` and `--add-dirs-ro` flags, but this implementation does not use them.

The `~/workspace` directory is already read-only inside the sandbox by default, so agents can read across projects without explicit mounts. `add-context` grants **write** access to specific additional directories via `--add-dirs`.

**Environment propagation:** The sandbox wrapper propagates the caller's environment to the child process (no env scrubbing). This is important because `vim.fn.termopen()` sets `TMUX=""` and `STY=""` to prevent raw base64 OSC 52 sequences from leaking to the display — these must reach the agent binary.

### Per-Agent Permission Flags

Since the sandbox controls filesystem permissions, agents should run in their most permissive mode. The permission flags are baked into `claude.lua:command()` per agent and apply unconditionally (both with and without the sandbox wrapper):

| Agent | Flag |
|-------|------|
| claude | `--dangerously-skip-permissions` |
| codex | `--full-auto` |
| opencode | (none needed) |

**Note on codex:** The current local-mode code uses `--dangerously-skip-permissions` for codex. The Docker path uses `--search --full-auto`. This spec intentionally changes codex local mode to `--full-auto` (without `--search`). `--full-auto` enables autonomous mode which bypasses interactive approval. The `--search` flag is a codex Docker-mode convention and is not carried over.

These flags were previously added in `init.lua`'s local branch. They move into `claude.lua:command()` so the command builder owns the full command string. In fallback mode (no sandbox), the same flags apply — the user gets the same autonomous behavior, just without filesystem isolation.

### Changes to `claude.lua`

The `command()` function signature changes from:

```lua
function M.command(args, command_name)
```

to:

```lua
function M.command(args, command_name, context_directories)
```

**`context_directories`** is the same table from `init.lua` (keys are absolute paths, values are `true`). When non-empty, keys are collected via `vim.tbl_keys()`, sorted with `table.sort()` for deterministic output, then joined with `:` into an `--add-dirs=<joined>` argument.

**Command construction order:**

1. Sandbox wrapper path (if available)
2. `--add-dirs=<dir1>:<dir2>:...` (if `context_directories` is non-empty)
3. Agent binary path (resolved via `command -v`)
4. Per-agent permission flag (unconditional, if applicable)
5. Caller-provided args

Example output (sandbox available):

```
~/.config/sandbox-exec/run-sandboxed.sh --add-dirs=/Users/foo/other-project /nix/store/.../claude --dangerously-skip-permissions /Users/foo/workspace/my-project
```

Example output (sandbox unavailable fallback):

```
/nix/store/.../claude --dangerously-skip-permissions /Users/foo/workspace/my-project
```

**Fallback behavior:** If the sandbox wrapper is not executable, `command()` falls back to direct binary execution (no sandbox) and emits a one-time `vim.notify` at WARN level. The check uses `vim.fn.executable(wrapper_path) == 1`, runs once at require-time, and caches the result in a module-level local boolean `sandbox_available`. Changes to the wrapper require restarting Neovim. This is a known limitation — no health check or hot-reload is provided.

**`command()` never returns nil.** If the agent binary is not found, `command()` emits an error via `vim.api.nvim_err_writeln()` and returns nil. Callers (`start_new_agent_job`) must guard against nil and abort early with an error notification. This is a pre-existing issue in the current code but the spec requires the caller guard since the sandbox adds another potential failure path.

**`CLAUDE_CONFIG_DIR` env var prefix:** Currently prepended for claude/codex via string concatenation in the command. This is dropped. The sandbox's default profile grants read access to `~/.config`, and the agent CLIs find their config at their default paths. This assumes `XDG_CONFIG_HOME` is the standard `~/.config` — if it has been customized, agent config resolution may need to be updated separately. The env var was originally added as a workaround for Docker's isolated filesystem.

### Changes to `init.lua`

#### Local branch simplification

In `start_new_agent_job()`, the local branch (lines ~306-321) simplifies:

**Before:**
```lua
local final_args = vim.tbl_extend("force", {}, default_args)
if command_name ~= "opencode" then
    table.insert(final_args, "--dangerously-skip-permissions")
end
if args and #args > 0 then
    vim.list_extend(final_args, args)
end
command = claude.command(final_args, command_name)
```

**After:**
```lua
local final_args = vim.tbl_extend("force", {}, default_args)
if args and #args > 0 then
    vim.list_extend(final_args, args)
end
command = claude.command(final_args, command_name, M.context_directories)
if not command then
    log.error("Failed to build command for " .. command_name, true)
    return
end
```

The `--dangerously-skip-permissions` logic is removed from `init.lua` — `claude.lua:command()` owns per-agent flags now. A nil guard is added since `command()` can return nil if the binary isn't found.

#### New public helper: `M.restart_local_agent()`

The private function `get_mode_vars()` (init.lua:59) cannot be called from `commands.lua`. Rather than exporting it, add a public method on `M` that encapsulates the local-mode restart sequence:

```lua
function M.restart_local_agent()
    -- Check if there's actually a running local agent (not just default active_mode)
    local mode = M.active_mode
    if mode == "none" or mode:match("-docker$") then
        return false -- not a local agent mode
    end
    -- Verify a buffer/job actually exists (active_mode defaults to "opencode" at module
    -- load even before any agent is started)
    if not M.active_buf or not vim.api.nvim_buf_is_valid(M.active_buf) then
        return false -- no running local agent
    end
    local vars = get_mode_vars(mode)
    local buf = M[vars.buf_key]
    local job_id = M[vars.job_key]
    if buf then
        terminal.close_terminal_buffer(buf, job_id)
    end
    M[vars.buf_key] = nil
    M[vars.job_key] = nil
    M.active_buf = nil
    M.active_job_id = nil
    M.active_mode = "none"
    -- Re-open with the captured mode (not M.active_mode, which is now "none")
    M.Open(mode)
    return true
end
```

Key details:
- `mode` is captured **before** clearing state. `M.Open(mode)` uses the captured value.
- The function checks `M.active_buf` validity, not just `active_mode`, to avoid false positives when `active_mode` is its default value (`"opencode"`) but no agent is running.
- Returns `true` on success, `false` if no local agent was running. Callers must handle `false` — see `restart_agent_with_context()` below.
- **Args are not preserved on restart.** This is intentional: the git root path arg for opencode is re-derived from `util.get_git_root()` inside `start_new_agent_job()`. WorkmuxPrompt `--prompt` args are one-time startup args and are not meaningful on restart.

No other changes to `init.lua`. The Docker branch is untouched.

### Changes to `commands.lua`

#### `add-context` and `remove-context`

These handlers currently assume Docker mode for restarts. They need to branch on whether the active mode is Docker or local.

**Restart helper:** Both `add-context` and `remove-context` use the same restart dispatch logic. Extract this into a local helper:

```lua
local function restart_agent_with_context(agent_module, action_desc)
    local mode = agent_module.active_mode

    -- Docker mode: use active_buf/active_job_id to close terminal, then container restart
    if mode:match("-docker$") then
        if not agent_module.container_started then
            vim.notify(action_desc .. " — context will be applied when container starts", vim.log.levels.INFO)
            return
        end
        -- Close the active Docker terminal buffer
        if agent_module.active_buf and vim.api.nvim_buf_is_valid(agent_module.active_buf) then
            terminal.close_terminal_buffer(agent_module.active_buf, agent_module.active_job_id)
            -- Clear the mode-specific fields via the active pointers
            -- (avoids needing get_mode_vars from commands.lua)
            agent_module.active_buf = nil
            agent_module.active_job_id = nil
            agent_module.active_mode = "none"
        end
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
    if not restarted then
        vim.notify(action_desc .. " — context will be applied when agent starts", vim.log.levels.INFO)
    end
end
```

This helper:
- Is synchronous (terminal close + Docker/agent restart are fire-and-forget async internally, but the helper itself returns immediately)
- Uses `active_buf`/`active_job_id` for Docker mode instead of the broken `docker_buf` field references — avoids needing `get_mode_vars()` from `commands.lua`
- When `restart_local_agent()` returns `false`, defers the context change to next agent start with a user-visible notification
- `action_desc` is used in the deferred notification (e.g., "Added context: /foo")

**Docker mode restart path (bug fix):** The existing Docker restart code in `handle_add_context` (commands.lua:319-329) and `handle_remove_context` (commands.lua:368-378) references nonexistent fields `claude_module.docker_buf` and `claude_module.docker_job_id`. These are dead code from before the multi-mode refactor. The new `restart_agent_with_context()` helper fixes this by using `active_buf`/`active_job_id` directly.

**`remove-context` with empty table:** If the last context directory is removed, the agent restarts with no `--add-dirs` flag. This is correct — the agent runs with only the sandbox's default permissions.

#### Docker-only subcommands

The following subcommands only apply in Docker mode: `build`, `restart`, `shell`, `container-logs`, `check-firewall`.

**`shell`, `container-logs`, `check-firewall`** already have their own `docker.is_container_running()` checks internally (commands.lua:455, 497, 556). These runtime checks are correct and should be preserved — they accurately reflect whether the container is actually running. No additional guard is needed.

**`build`** operates on the Docker image, not a running container, so it needs no guard. It works regardless of mode.

**`restart`** operates on Docker containers. It currently handles both "container running" and "container not running" cases (commands.lua:252-289), calling `start_container_async()` unconditionally. This is useful for starting a container from scratch or after a crash. No hard guard is added — `restart` remains usable in all states.

**Net change for Docker-only subcommands:** None of these handlers need new guards. The existing runtime checks (`is_container_running()`) are correct. The only risk was that the spec might accidentally break `restart` with an overzealous guard — this is avoided by leaving the existing behavior alone.

#### `list-contexts`

Works as-is since it reads `context_directories`. The display message adapts based on `active_mode`:

- Docker mode (`active_mode` matches `-docker$`): existing display with source path → `/context/<name>` mount mapping, including duplicate detection with hash suffix
- Local mode or no agent: "Context directories (sandbox write access):" with numbered source paths only (no mount mapping, no duplicate detection needed since there are no container mount targets)

### What doesn't change

- **Docker container lifecycle internals** (`docker/init.lua`): Image builds, container start/stop, firewall setup, volume mounts, worktree detection — all unchanged.
- **Docker `add-context`/`remove-context` behavior** is fixed (dead field references replaced with `active_buf`/`active_job_id`), but the user-visible behavior is the same.
- **Keymaps**: Same keymaps, same mode strings. `<leader>co` toggles `"opencode"`, `<leader>cO` toggles `"opencode-docker"`.
- **Buffer management**: `terminal.lua`, `buffer-config.lua` — no changes.
- **State tracking**: Same `M.*_buf`, `M.*_job_id`, `active_mode`/`active_buf`/`active_job_id` pattern. `active_mode` is always a non-nil string (initialized to `"opencode"` at module load, set to `"none"` on exit). Note: `"opencode"` at module load does **not** mean an agent is running — `restart_local_agent()` checks `active_buf` validity to distinguish.
- **Send functions**: `SendText`, `SendCommand`, `SendSelection`, `SendFile`, `SendOpenBuffers`, `WorkmuxPrompt` — all unchanged.
- **`util.lua`**: Unchanged.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Sandbox wrapper not found | Fall back to direct execution, one-time WARN notification |
| Agent binary not found | `command()` returns nil, caller aborts with error |
| `add-context` with no running agent | Record directory, notify "will be applied when agent starts" |
| `add-context` in Docker mode | Close terminal via `active_buf`, container restart (bug fix) |
| `add-context` in local mode | Close terminal, re-launch with updated `--add-dirs` |
| `add-context` duplicate directory | Notify "Context already added" (existing behavior, preserved) |
| `add-context` invalid directory | Notify "Directory does not exist" (existing behavior, preserved) |
| `remove-context` with no running agent | Remove directory, notify "Context removed" |
| `remove-context` removing last directory | Agent restarts with no `--add-dirs` flag |
| `remove-context` directory not found | Notify "Context not found" (existing behavior, preserved) |
| `remove-context` in Docker mode | Close terminal via `active_buf`, container restart (bug fix) |
| `remove-context` in local mode | Close terminal, re-launch without removed directory |
| `VimLeavePre` in local mode | Existing `cleanup()` stops jobs; no special sandbox teardown needed |

### Testing

- **Command string format** (manual): verify `claude.command()` output with empty, single, and multiple `context_directories` — paths should be sorted and colon-joined
- **Per-agent flags** (manual): verify claude gets `--dangerously-skip-permissions`, codex gets `--full-auto`, opencode gets no flag — in both sandbox and fallback modes
- **Fallback behavior** (manual): verify that when sandbox wrapper is absent, `command()` returns a direct binary command and warns once
- **Nil guard** (manual): verify that when agent binary is not found, `start_new_agent_job` aborts gracefully
- **`restart_local_agent()` mode capture** (manual): verify that after restart, the agent re-opens in the same mode (not `"none"`)
- **`restart_local_agent()` with no running agent** (manual): verify returns `false` and caller notifies user
- **`add-context` restart in local mode** (manual): verify old terminal is closed and new one opens with updated `--add-dirs`
- **`add-context` restart in Docker mode** (manual): verify uses `active_buf`/`active_job_id` (not dead `docker_buf` field)
- **`remove-context` with empty table** (manual): verify agent restarts with no `--add-dirs`
- **`list-contexts` display** (manual): verify output adapts between Docker and local modes
- **Existing error handling preserved** (manual): verify duplicate add, invalid directory, and remove-not-found still produce correct notifications
