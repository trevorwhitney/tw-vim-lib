#!/usr/bin/env bash
# Deterministic stand-in for opencode in acceptance runs. Speaks to agentd
# exactly like the real plugin: session self-registration plus report or
# escalate over the unix socket. Behavior is selected by AGENTD_FAKE_MODE:
#   report   (default) register session, deliver an approving report
#   escalate           register session, ask a question; on --session
#                      continuation, deliver the report
set -euo pipefail

post() {
  curl -sf --unix-socket "$AGENTD_SOCKET" -X POST "http://agentd$1" \
    -H 'content-type: application/json' -d "$2" > /dev/null
}

case "${1:-}" in
export)
  echo '{"fake_transcript": true, "session": "'"${2:-}"'"}'
  exit 0
  ;;
run)
  mode="${AGENTD_FAKE_MODE:-report}"
  token="${AGENTD_JOB_TOKEN}"
  if [[ "$*" == *"--session"* ]]; then
    post "/jobs/$token/report" \
      '{"verdict":"approve","summary":"continued after answer","details":"resumed and finished"}'
    exit 0
  fi
  post "/jobs/$token/session" '{"session_id":"ses_fake_'"$token"'"}'
  if [[ "$mode" == "escalate" ]]; then
    post "/jobs/$token/escalate" \
      '{"kind":"question","question":"which base branch?","context":"acceptance"}'
  else
    post "/jobs/$token/report" \
      '{"verdict":"approve","summary":"acceptance approve","details":"fake analysis"}'
  fi
  exit 0
  ;;
*)
  echo "fake-opencode: unhandled args: $*" >&2
  exit 1
  ;;
esac
