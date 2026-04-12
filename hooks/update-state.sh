#!/usr/bin/env bash
set -euo pipefail

# update-state.sh — Update .beacon/state.json for a given issue.
# Usage: update-state.sh <action> <issue-id> [key=value ...]
# Actions: set-claimed, set-running, set-verifying, set-completed, set-blocked, set-merged, set-failed

BEACON_DIR=".beacon"
STATE_FILE="$BEACON_DIR/state.json"

# Locate repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
STATE_FILE="$REPO_ROOT/$STATE_FILE"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: $STATE_FILE not found. Run beacon-init.sh first." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found" >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <action> <issue-id> [key=value ...]" >&2
  echo "Actions: set-claimed, set-running, set-verifying, set-completed, set-blocked, set-merged, set-failed" >&2
  exit 1
fi

ACTION="$1"
ISSUE_ID="$2"
shift 2

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Cleanup temp files on exit
TMP_FILES=()
cleanup() { for f in "${TMP_FILES[@]}"; do rm -f "$f"; done; }
trap cleanup EXIT

make_tmp() { local t; t=$(mktemp); TMP_FILES+=("$t"); echo "$t"; }

# Map action to state and stat counter
case "$ACTION" in
  set-claimed)
    NEW_STATE="claimed"
    STAT_KEY=""
    ;;
  set-running)
    NEW_STATE="running"
    STAT_KEY="dispatched"
    ;;
  set-verifying)
    NEW_STATE="verifying"
    STAT_KEY=""
    ;;
  set-completed)
    NEW_STATE="approved"
    STAT_KEY="completed"
    ;;
  set-blocked)
    NEW_STATE="blocked"
    STAT_KEY="blocked"
    ;;
  set-merged)
    NEW_STATE="merged"
    STAT_KEY="completed"
    ;;
  set-failed)
    NEW_STATE="blocked"
    STAT_KEY="failed"
    ;;
  *)
    echo "Error: unknown action '$ACTION'" >&2
    echo "Valid actions: set-claimed, set-running, set-verifying, set-completed, set-blocked, set-merged, set-failed" >&2
    exit 1
    ;;
esac

# Ensure the issue entry exists (initialize if new)
CURRENT=$(jq -r --arg id "$ISSUE_ID" '.issues[$id] // empty' "$STATE_FILE")
if [[ -z "$CURRENT" ]]; then
  # Create a new issue entry
  TMP=$(make_tmp)
  jq --arg id "$ISSUE_ID" --arg now "$NOW" \
    '.issues[$id] = {"state": "unclaimed", "complexity": "medium", "agent": "", "attempt": 1, "worktree": "", "pane_id": "", "started_at": $now, "attempts_history": []}' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
fi

# Update state and timestamp
TMP=$(mktemp)
jq --arg id "$ISSUE_ID" --arg state "$NEW_STATE" --arg now "$NOW" \
  '.issues[$id].state = $state | .updated_at = $now' \
  "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"

# Increment stat counter if applicable
if [[ -n "$STAT_KEY" ]]; then
  TMP=$(make_tmp)
  jq --arg key "$STAT_KEY" \
    '.stats[$key] += 1' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
fi

# Apply optional key=value overrides
for pair in "$@"; do
  KEY="${pair%%=*}"
  VALUE="${pair#*=}"
  TMP=$(make_tmp)
  # Try to parse as JSON (for numbers/booleans), fall back to string
  if echo "$VALUE" | jq -e '.' >/dev/null 2>&1; then
    jq --arg id "$ISSUE_ID" --arg key "$KEY" --argjson val "$VALUE" \
      '.issues[$id][$key] = $val' \
      "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
  else
    jq --arg id "$ISSUE_ID" --arg key "$KEY" --arg val "$VALUE" \
      '.issues[$id][$key] = $val' \
      "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
  fi
done

echo "Updated issue $ISSUE_ID: state=$NEW_STATE"
