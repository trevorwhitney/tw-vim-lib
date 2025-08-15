#!/bin/bash

# Read JSON from stdin
json_input=$(cat)

# Add required fields from environment
json_with_env=$(echo "$json_input" | jq --arg nvim "$NVIM" --arg tag "${CC_SESSION_TAG:-unknown}" --arg channel "${CC_CHANNEL:-}" '. + {
  nvim_server: $nvim,
  session_tag: $tag,
  channel: (if $channel == "" then null else ($channel | tonumber) end)
}')

# Send to Claude Inbox
curl -sS -X POST "${CLAUDE_INBOX_URL:-http://127.0.0.1:43111/events}" \
  -H "Content-Type: application/json" \
  -d "$json_with_env" \
  > /dev/null 2>&1

# Always exit 0 to not block Claude
exit 0