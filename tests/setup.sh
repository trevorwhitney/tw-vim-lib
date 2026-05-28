#!/usr/bin/env bash
# Bootstrap plenary.nvim and pin to a specific commit. Idempotent: if the
# clone is already present, fetch and check out the pinned ref so the
# working tree matches the pin.
set -euo pipefail
PLENARY_REF="74b06c6c75e4eeb3108ec01852001636d85a932b"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$ROOT/tests/.deps"
PLENARY_DIR="$DEPS/plenary.nvim"
mkdir -p "$DEPS"
if [ ! -d "$PLENARY_DIR/.git" ]; then
  git clone https://github.com/nvim-lua/plenary.nvim.git "$PLENARY_DIR"
fi
git -C "$PLENARY_DIR" fetch --quiet origin "$PLENARY_REF" 2>/dev/null || \
  git -C "$PLENARY_DIR" fetch --quiet origin
git -C "$PLENARY_DIR" checkout --quiet "$PLENARY_REF"
