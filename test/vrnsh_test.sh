#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$VRNSH_CAPTURE"
printf '%s' "$VRNSH_ORIGINAL_PATH" >"$VRNSH_PATH_CAPTURE"
printf '%s' "$PATH" >"$VRNSH_NVIM_PATH_CAPTURE"
EOF
chmod +x "$tmp/nvim"

export VRNSH_CAPTURE="$tmp/capture"
export VRNSH_NVIM_PATH_CAPTURE="$tmp/nvim-path-capture"
export VRNSH_PATH_CAPTURE="$tmp/path-capture"
launcher_path="$tmp:$PATH"
PATH="$launcher_path" bash "$root/bin/vrnsh" claude \
  --model opus \
  --prompt "build me a plugin" \
  "quote' and space" \
  '$(printf injected)' \
  ""

mapfile -d '' nvim_args <"$VRNSH_CAPTURE"
[[ ${#nvim_args[@]} -eq 1 ]]
[[ ${nvim_args[0]} == "+AgentFullscreen claude "* ]]

forwarded=${nvim_args[0]#"+AgentFullscreen claude "}
eval "set -- $forwarded"
literal_command_substitution="\$(printf injected)"
[[ $# -eq 7 ]]
[[ $1 == "--model" ]]
[[ $2 == "opus" ]]
[[ $3 == "--prompt" ]]
[[ $4 == "build me a plugin" ]]
[[ $5 == "quote' and space" ]]
[[ $6 == "$literal_command_substitution" ]]
[[ $7 == "" ]]
[[ $(<"$VRNSH_PATH_CAPTURE") == "$launcher_path" ]]
[[ $(<"$VRNSH_NVIM_PATH_CAPTURE") == "/usr/bin:/bin" ]]

if PATH="$tmp:$PATH" bash "$root/bin/vrnsh" unknown 2>"$tmp/error"; then
  printf 'expected unknown agent to fail\n' >&2
  exit 1
fi
grep -q "unknown agent: unknown" "$tmp/error"

PATH="$tmp:$PATH" bash "$root/bin/vrnsh" --help >"$tmp/help"
grep -q "vrnsh <opencode|claude|codex>" "$tmp/help"

printf 'vrnsh tests passed\n'
