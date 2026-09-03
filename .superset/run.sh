#!/usr/bin/env bash
# There is no dev server in this repo — the "app" is Neovim itself, built from
# this worktree's flake. Launch it inside the devShell so you're exercising the
# config you're editing. Extra args are passed through to nvim.
set -euo pipefail

cd "${SUPERSET_WORKSPACE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export PATH="$PATH:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin"

if command -v direnv >/dev/null 2>&1 && direnv exec . true >/dev/null 2>&1; then
  exec direnv exec . nvim "$@"
fi

exec nix develop --command nvim "$@"
