#!/usr/bin/env bash
set -euo pipefail

# check-completion.sh — Detect completed agent panes in the beacon tmux session.
# Parses dead panes and extracts tool/issue-key from pane titles (format: "TOOL: issue-key").
# Outputs JSON with completed pane info.

# Check if beacon tmux session exists
PANE_OUTPUT=$(tmux list-panes -t beacon -F '#{pane_id} #{pane_dead} #{pane_title}' 2>/dev/null) || {
  echo '{"completed": []}'
  exit 0
}

# Parse dead panes into JSON array
COMPLETED="[]"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  PANE_ID=$(echo "$line" | awk '{print $1}')
  DEAD=$(echo "$line" | awk '{print $2}')
  TITLE=$(echo "$line" | cut -d' ' -f3-)

  # Only process dead panes
  [[ "$DEAD" != "1" ]] && continue

  # Extract tool and issue key from title format "TOOL: issue-key"
  if [[ "$TITLE" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
    TOOL="${BASH_REMATCH[1]}"
    ISSUE_KEY="${BASH_REMATCH[2]}"

    # Append to JSON array using jq if available, else build manually
    if command -v jq >/dev/null 2>&1; then
      COMPLETED=$(echo "$COMPLETED" | jq -c \
        --arg pid "$PANE_ID" \
        --arg tool "$TOOL" \
        --arg key "$ISSUE_KEY" \
        '. + [{"pane_id": $pid, "tool": $tool, "issue_key": $key}]')
    else
      # Fallback: manual JSON construction
      ENTRY=$(printf '{"pane_id":"%s","tool":"%s","issue_key":"%s"}' "$PANE_ID" "$TOOL" "$ISSUE_KEY")
      if [[ "$COMPLETED" == "[]" ]]; then
        COMPLETED="[$ENTRY]"
      else
        COMPLETED="${COMPLETED%]},$ENTRY]"
      fi
    fi
  fi
done <<< "$PANE_OUTPUT"

echo "{\"completed\": $COMPLETED}"
