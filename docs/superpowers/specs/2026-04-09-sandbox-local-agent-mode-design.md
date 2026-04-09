# Sandbox Local Agent Mode

## Problem

The `:AiAgent` command system has two execution modes: local (raw binary) and Docker (containerized). Local mode runs agent CLIs directly with no isolation — the agent has full access to the filesystem. Docker mode provides isolation but adds overhead (image builds, container lifecycle, firewall setup) and doesn't work well on macOS where Docker Desktop performance is poor.

A macOS sandbox wrapper (`~/.config/sandbox-exec/run-sandboxed.sh`) exists that sandboxes agent CLIs with a deny-by-default policy. It provides filesystem isolation comparable to Docker with none of the overhead. The agent module needs to use this wrapper for all local agent invocations.

## Goal

Replace the unsandboxed local execution path with sandboxed execution via `run-sandboxed.sh`. In local mode, all agent commands are wrapped through the sandbox. The `add-context` subcommand grants write access to additional directories by passing `--add-dirs` to the wrapper and restarting the agent. Docker mode is unchanged.

## Design

### Sandbox Wrapper Contract

The wrapper lives at `~/.config/sandbox-exec/run-sandboxed.sh` (hardcoded, not configurable). It accepts:

```
run-sandboxed.sh [--workdir=<path>] [--add-dirs=<p1:p2:...>] [--add-dirs-ro=<p1:p2:...>] <command> [args...]
```

- `--add-dirs`: colon-separated paths granted read/write access
- `--add-dirs-ro`: colon-separated paths granted read-only access
- `<command>`: the agent binary path, followed by its arguments
- No `--` separator needed between wrapper flags and the command

The `~/workspace` directory is already read-only inside the sandbox by default, so agents can read across projects without explicit mounts. `add-context` grants **write** access to specific additional directories via `--add-dirs`.

### Per-Agent Permission Flags

Since the sandbox controls filesystem permissions, agents should run in their most permissive mode. The permission flags are baked into `claude.lua:command()` per agent:

| Agent | Flag |
|-------|------|
| claude | `--dangerously-skip-permissions` |
| codex | `--full-auto` |
| opencode | (none needed) |

These flags were previously added in `init.lua`'s local branch. They move into `claude.lua:command()` so the command builder owns the full command string.

### Changes to `claude.lua`

The `command()` function signature changes from:

```lua
function M.command(args, command_name)
```

to:

```lua
function M.command(args, command_name, context_directories)
```

**`context_directories`** is the same table from `init.lua` (keys are absolute paths, values are `true`). When non-empty, paths are joined with `:` into an `--add-dirs=<joined>` argument.

**Command construction order:**

1. Sandbox wrapper path
2. `--add-dirs=<dir1>:<dir2>:...` (if `context_directories` is non-empty)
3. Agent binary path (resolved via `command -v`)
4. Per-agent permission flag (if applicable)
5. Caller-provided args

Example output:

```
~/.config/sandbox-exec/run-sandboxed.sh --add-dirs=/Users/foo/other-project /nix/store/.../claude --dangerously-skip-permissions /Users/foo/workspace/my-project
```

**Fallback behavior:** If the sandbox wrapper doesn't exist or isn't executable, `command()` falls back to direct binary execution (no sandbox) and emits a one-time `vim.notify` at WARN level. This keeps the plugin functional on machines without the sandbox installed. The fallback check runs once at require-time and caches the result.

**`CLAUDE_CONFIG_DIR` env var prefix:** Currently prepended for claude/codex. This is dropped — the sandbox controls the environment.

### Changes to `init.lua`

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
```

The `--dangerously-skip-permissions` logic is removed from `init.lua` — `claude.lua:command()` owns per-agent flags now.

No other changes to `init.lua`. The Docker branch is untouched.

### Changes to `commands.lua`

#### `add-context` and `remove-context`

These handlers currently assume Docker mode for restarts. They need to branch on whether the active mode is Docker or local.

**Detection:** `agent_module.active_mode:match("-docker$")` distinguishes the two paths.

**Docker mode (existing behavior, unchanged):**
1. Close Docker buffer
2. Stop container
3. Restart container with updated `context_directories`

**Local/sandbox mode (new behavior):**
1. Find the active local-mode buffer and job from `agent_module` using `get_mode_vars(active_mode)`
2. Close the terminal buffer (kills the sandboxed process)
3. Clear buffer/job state and active pointers
4. Call `agent_module.Open(agent_module.active_mode)` to re-launch with updated `context_directories`

When no agent is running (neither Docker container nor local terminal), both modes record the directory and notify "Context will be applied when agent starts."

**Restart helper:** The local-mode restart logic (close terminal, clear state, re-open) is used by both `add-context` and `remove-context`. Extract it into a local helper function to avoid duplication.

#### Docker-only subcommands

The following subcommands only apply in Docker mode: `build`, `restart`, `shell`, `container-logs`, `check-firewall`.

Each gets a guard at the top:

```lua
if not agent_module.active_mode:match("-docker$") then
    vim.notify("This command is only available in Docker mode", vim.log.levels.WARN)
    return
end
```

Note: the guard checks `active_mode` which could be `"none"` or a local mode. The intent is that these commands are only meaningful when actively using Docker mode.

#### `list-contexts`

Works as-is since it reads `context_directories`. The display message adapts:

- Docker mode: "Context directories mounted in container:" with `/context/<name>` mount paths (existing)
- Local mode: "Context directories (sandbox write access):" with just the source paths listed

### What doesn't change

- **Docker mode** (`*-docker` variants): Container lifecycle, firewall, volume mounts, worktree detection — all unchanged.
- **Keymaps**: Same keymaps, same mode strings. `<leader>co` toggles `"opencode"`, `<leader>cO` toggles `"opencode-docker"`.
- **Buffer management**: `terminal.lua`, `buffer-config.lua` — no changes.
- **State tracking**: Same `M.*_buf`, `M.*_job_id`, `active_mode`/`active_buf`/`active_job_id` pattern.
- **Send functions**: `SendText`, `SendCommand`, `SendSelection`, `SendFile`, `SendOpenBuffers`, `WorkmuxPrompt` — all unchanged.
- **`util.lua`**: Unchanged.
- **`docker/init.lua`**: Unchanged.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Sandbox wrapper not found | Fall back to direct execution, one-time WARN notification |
| `add-context` with no running agent | Record directory, notify "will be applied when agent starts" |
| `add-context` in Docker mode | Existing container restart (unchanged) |
| `add-context` in local mode | Close terminal, re-launch with updated `--add-dirs` |
| Docker-only subcommand in local mode | Notify "only available in Docker mode", return |
| `VimLeavePre` in local mode | Existing `cleanup()` stops jobs; no special sandbox teardown needed |

### Testing

- Verify sandboxed command string format with different combinations of `context_directories` (empty, single, multiple)
- Verify fallback when sandbox wrapper is absent
- Verify `add-context` restart in local mode closes old terminal and opens new one
- Verify Docker-only subcommands are guarded
- Verify `list-contexts` adapts display text to mode
