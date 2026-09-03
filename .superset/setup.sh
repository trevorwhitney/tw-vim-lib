#!/usr/bin/env bash
# Prepare a fresh Superset workspace for tw-vim-lib.
#
# The repo is a Neovim config library with a Nix flake devShell (entered via
# direnv) plus two test harnesses that need gitignored, per-worktree state:
#   - tests/.deps/plenary.nvim (cloned by tests/setup.sh)
#   - test/vendor (optional Go vendor dir; `go test` also works from the cache)
set -euo pipefail

cd "${SUPERSET_WORKSPACE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# direnv/nix are installed outside the default PATH on some setups.
export PATH="$PATH:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin"

# 1. Trust the .envrc so the flake devShell loads on `cd` into the worktree.
if command -v direnv >/dev/null 2>&1; then
  echo "==> direnv allow"
  direnv allow .
else
  echo "!! direnv not found on PATH; skipping 'direnv allow'." >&2
  echo "   Run it manually in this worktree before using the devShell." >&2
fi

# 2. Warm the devShell so the first terminal isn't stuck building. flake.lock is
#    shared with the root repo, so this is usually a store-cache hit.
if command -v nix >/dev/null 2>&1; then
  echo "==> warming nix devShell (cached unless flake.lock changed)"
  nix develop --command true || {
    echo "!! nix develop failed; the devShell will retry on first cd." >&2
  }
fi

# 3. Plenary test dependency. Reuse the root repo's clone when present (fast
#    local copy), otherwise fall back to the repo's own bootstrap script.
if [ -n "${SUPERSET_ROOT_PATH:-}" ] && [ -d "$SUPERSET_ROOT_PATH/tests/.deps/plenary.nvim/.git" ] \
  && [ ! -d tests/.deps/plenary.nvim/.git ]; then
  echo "==> copying tests/.deps from $SUPERSET_ROOT_PATH"
  mkdir -p tests/.deps
  cp -R "$SUPERSET_ROOT_PATH/tests/.deps/plenary.nvim" tests/.deps/
fi
echo "==> tests/setup.sh (pin plenary.nvim)"
./tests/setup.sh

# 4. Go harness deps. Nothing to vendor unless the root repo already did; the
#    module cache is shared, so `make test-go` works either way.
if [ -n "${SUPERSET_ROOT_PATH:-}" ] && [ -d "$SUPERSET_ROOT_PATH/test/vendor" ] && [ ! -d test/vendor ]; then
  echo "==> copying test/vendor from $SUPERSET_ROOT_PATH"
  cp -R "$SUPERSET_ROOT_PATH/test/vendor" test/vendor
fi

echo "==> workspace ready: make lint | make test | make format"
