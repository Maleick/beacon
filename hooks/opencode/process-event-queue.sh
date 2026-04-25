#!/usr/bin/env bash
set -euo pipefail

AUTOSHIP_DIR=".autoship"
EVENT_QUEUE="$AUTOSHIP_DIR/event-queue.json"
PROCESSED_EVENTS="$AUTOSHIP_DIR/processed-events.json"
LOCK_FILE="$AUTOSHIP_DIR/event-queue.lock"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found" >&2
  exit 1
fi

if [[ -z "${AUTOSHIP_QUEUE_LOCKED:-}" ]]; then
  export AUTOSHIP_QUEUE_LOCKED=1
  mkdir -p "$AUTOSHIP_DIR"
  touch "$LOCK_FILE"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -x 9
  elif command -v lockf >/dev/null 2>&1; then
    exec lockf -k "$LOCK_FILE" "$0" "$@"
  fi
fi

make_tmp() { mktemp "$AUTOSHIP_DIR/event-queue.tmp.XXXXXX"; }

ensure_array_file() {
  local file="$1"
  local tmp
  if [[ ! -f "$file" ]] || ! jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
    tmp=$(make_tmp)
    printf '[]\n' > "$tmp"
    mv "$tmp" "$file"
  fi
}

event_key() {
  jq -c '[
    (.type // ""),
    (.issue // ""),
    (.data.status // .status // ""),
    (.pr_number // .data.pr_number // ""),
    (.action // "")
  ]' <<< "$1"
}

is_processed() {
  local key="$1"
  jq -e --arg key "$key" 'index($key) != null' "$PROCESSED_EVENTS" >/dev/null
}

mark_processed() {
  local key="$1"
  local tmp
  tmp=$(make_tmp)
  jq --arg key "$key" 'if index($key) then . else . + [$key] end' \
    "$PROCESSED_EVENTS" > "$tmp" && mv "$tmp" "$PROCESSED_EVENTS"
}

current_state() {
  local issue="$1"
  jq -r --arg issue "$issue" '.issues[$issue].state // empty' "$AUTOSHIP_DIR/state.json" 2>/dev/null || true
}

apply_state_once() {
  local issue="$1"
  local action="$2"
  local target_state="$3"
  local current

  current=$(current_state "$issue")
  case "$current" in
    "$target_state"|merged)
      return 0
      ;;
  esac

  bash "$SCRIPT_DIR/../update-state.sh" "$action" "$issue"
}

process_event() {
  local event="$1"
  local type issue
  type=$(jq -r '.type // empty' <<< "$event")
  issue=$(jq -r '.issue // empty' <<< "$event")

  case "$type" in
    blocked)
      [[ -n "$issue" ]] || return 1
      apply_state_once "$issue" set-blocked blocked
      ;;
    stuck)
      [[ -n "$issue" ]] || return 1
      apply_state_once "$issue" set-stuck stuck
      ;;
    verify)
      [[ -n "$issue" ]] || return 1
      apply_state_once "$issue" set-verifying verifying
      ;;
    force_dispatch)
      [[ -n "$issue" ]] || return 1
      local state number task_type
      state=$(current_state "$issue")
      case "$state" in
        queued|running|verifying|completed|merged|blocked)
          return 0
          ;;
      esac
      number="${issue#issue-}"
      task_type=$(bash "$SCRIPT_DIR/classify-issue.sh" "$number")
      bash "$SCRIPT_DIR/dispatch.sh" "$number" "$task_type"
      bash "$SCRIPT_DIR/runner.sh"
      ;;
    *)
      echo "Skipping unsupported event type: ${type:-<missing>}" >&2
      ;;
  esac
}

ensure_array_file "$EVENT_QUEUE"
ensure_array_file "$PROCESSED_EVENTS"

remaining_tmp=$(make_tmp)
printf '[]\n' > "$remaining_tmp"

while IFS= read -r event; do
  [[ -n "$event" ]] || continue
  key=$(event_key "$event")
  if is_processed "$key"; then
    continue
  fi

  if process_event "$event"; then
    mark_processed "$key"
  else
    next_remaining=$(make_tmp)
    jq --argjson evt "$event" '. + [$evt]' "$remaining_tmp" > "$next_remaining" && mv "$next_remaining" "$remaining_tmp"
  fi
done < <(jq -c '.[]' "$EVENT_QUEUE")

mv "$remaining_tmp" "$EVENT_QUEUE"
