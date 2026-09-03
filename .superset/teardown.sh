#!/usr/bin/env bash
# Undo what setup.sh created. No servers or containers here — the only external
# state is the nix GC root that nix-direnv registers for this worktree's
# .direnv, so release that before the worktree is removed.
set -uo pipefail

cd "${SUPERSET_WORKSPACE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export PATH="$PATH:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin"

if command -v direnv >/dev/null 2>&1; then
  echo "==> direnv revoke"
  direnv revoke . 2>/dev/null || direnv deny . 2>/dev/null || true
fi

echo "==> removing generated state (.direnv, tests/.deps, test/vendor, result, nvim.log)"
rm -rf .direnv tests/.deps test/vendor result nvim.log
