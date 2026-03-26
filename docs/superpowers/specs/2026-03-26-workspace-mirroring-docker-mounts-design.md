# Workspace-Mirroring Docker Mounts

## Problem

When AI agents run inside the Docker container, the host's current working directory is mounted at `/workspace`. If the agent encounters a reference to a sibling project (e.g., `../other-project`), that path does not exist inside the container because only the single CWD is mounted.

## Goal

Mirror the host's `~/workspace` directory structure inside the container so that cross-project references resolve at the same relative paths. An agent working in `~/workspace/project-a` should be able to access `~/workspace/project-b` at `../project-b` inside the container.

## Design

### Mount Strategy

A helper function determines whether the host CWD is under `~/workspace`:

```
host_workspace = vim.fn.expand("~/workspace")
cwd = vim.fn.getcwd()
is_under_workspace = cwd starts with host_workspace
```

**When CWD is under `~/workspace`:**
- Single bind mount: `~/workspace` → `/home/node/workspace`
- Container working directory derived by replacing the host prefix:
  - Host CWD: `~/workspace/project/worktree-1`
  - Container CWD: `/home/node/workspace/project/worktree-1`
- The agent starts via `docker exec -w /home/node/workspace/project/worktree-1`

**When CWD is NOT under `~/workspace` (fallback):**
- Mount host CWD → `/home/node/workspace` (single project, like today but at the new path)
- Container working directory: `/home/node/workspace`

### Dockerfile

Change `WORKDIR /workspace` to `WORKDIR /home/node/workspace`. Docker creates this directory automatically. Everything else in the Dockerfile is unchanged.

### Context Directories

The `:AiAgent add-context` feature mounts additional directories at `/context/<name>`.

**When under `~/workspace`:**
- Skip mounting any context dir that is already under `~/workspace` (already accessible)
- Mount dirs outside `~/workspace` at `/context/<name>` as before

**When in fallback mode:**
- All context dirs mount at `/context/<name>` as before

### OpenCode Project Path

OpenCode receives a project path as its first argument.

**When under `~/workspace`:**
- Translate the host git root to its container equivalent under `/home/node/workspace/...`
- No need to add git root to context directories
- Example: host git root `~/workspace/project/project` → container path `/home/node/workspace/project/project`

**When in fallback mode:**
- Same as current behavior but using `/home/node/workspace` instead of `/workspace`

### Worktree Handling

Git worktrees have a `.git` file containing a `gitdir:` path that points to the main repo's `.git/worktrees/<name>` directory. This path is absolute and host-specific, so it must be rewritten for the container.

**When worktree is under `~/workspace`:**
- The main repo is already accessible via the workspace mount — no `/git-root` mount needed
- Create a temp file with `gitdir:` rewritten to replace the host `~/workspace` prefix with `/home/node/workspace`
- Bind-mount the temp file over the container's `.git` path as read-only
- Example: host `gitdir: /Users/twhitney/workspace/project/project/.git/worktrees/worktree-1` → container `gitdir: /home/node/workspace/project/project/.git/worktrees/worktree-1`

**When worktree is NOT under `~/workspace` (fallback):**
- Same as current behavior: mount main repo at `/git-root`, rewrite to use `/git-root`, mount `.git` at `/home/node/workspace/.git:ro`

### `attach_to_container` Changes

Add a `working_dir` parameter so the agent starts in the correct subdirectory:

```lua
function M.attach_to_container(container_name, args, command, working_dir)
    -- ...
    local cmd = "docker exec -it -w " .. working_dir .. " " .. container_name
        .. ' /bin/bash -c "' .. cmd_string .. '"'
    return cmd
end
```

The caller in `init.lua` computes the working directory based on the mount strategy and passes it through.

## Files Changed

1. `lua/tw/agent/docker/Dockerfile` — Change `WORKDIR /workspace` to `WORKDIR /home/node/workspace`
2. `lua/tw/agent/docker/init.lua` — New mount logic in `get_start_container_command()`, updated `attach_to_container()` with `-w` flag, updated worktree path rewriting
3. `lua/tw/agent/init.lua` — Updated OpenCode project path derivation for workspace-mode, pass working dir to `attach_to_container()`

## Constants

- Host workspace path: `vim.fn.expand("~/workspace")` (resolved at runtime)
- Container workspace path: `/home/node/workspace`
- Container home: `/home/node` (unchanged from current)

## Testing

- Open Neovim in `~/workspace/project-a`, launch docker agent, verify `~/workspace/project-b` is accessible at `/home/node/workspace/project-b`
- Open Neovim in a git worktree under `~/workspace`, verify git operations work inside the container
- Open Neovim outside `~/workspace` (e.g., `/tmp/test`), verify fallback mounts `/tmp/test` at `/home/node/workspace`
- Add a context dir under `~/workspace` via `:AiAgent add-context`, verify it is skipped (no duplicate mount)
- Add a context dir outside `~/workspace`, verify it mounts at `/context/<name>`
- Launch OpenCode in docker mode, verify it receives the correct translated project path
