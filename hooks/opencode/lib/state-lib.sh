#!/usr/bin/env bash
# hooks/opencode/lib/state-lib.sh — State-manipulation primitives for AutoShip.
# Depends on common.sh (source common.sh before this file).

set -euo pipefail

# ── Lock acquisition ────────────────────────────────────────────
# Usage: autoship_state_lock [lock_file_path]
# Returns 0 on success, 1 if no lock mechanism available.
autoship_state_lock() {
  local state_file
  state_file="$(autoship_state_file)"
  local lock_file="${1:-${state_file%.json}.lock}"

  if [[ -z "${AUTOSHIP_STATE_LOCKED:-}" ]]; then
    export AUTOSHIP_STATE_LOCKED=1
    if command -v flock >/dev/null 2>&1; then
      if [[ -L "$lock_file" ]]; then
        echo "Error: refusing symlink lock file: $lock_file" >&2
        return 1
      fi
      exec 9>>"$lock_file"
      flock -x 9
      return 0
    elif command -v lockf >/dev/null 2>&1; then
      exec lockf -k "$lock_file" "$0" "$@"
      # Does not return — script is re-executed.
    fi
    # No lock mechanism available — proceed without locking.
    return 1
  fi
  return 0
}

# ── Safe state read ─────────────────────────────────────────────
# Usage: autoship_state_read [jq_filter] [default_value]
autoship_state_read() {
  local filter="${1:-.}"
  local default="${2:-}"
  local state_file
  state_file="$(autoship_state_file 2>/dev/null || true)"
  if [[ -f "${state_file:-}" ]]; then
    jq -r "$filter" "$state_file" 2>/dev/null || printf '%s' "$default"
  else
    printf '%s' "$default"
  fi
}

# ── Issue state read ────────────────────────────────────────────
# Usage: autoship_issue_state <issue-key>
autoship_issue_state() {
  local issue_key="$1"
  autoship_state_read --arg key "$issue_key" '.issues[$key].state // empty'
}

# ── Issue property read ─────────────────────────────────────────
# Usage: autoship_issue_property <issue-key> <property> [default]
autoship_issue_property() {
  local issue_key="$1"
  local prop="$2"
  local default="${3:-}"
  autoship_state_read --arg key "$issue_key" --arg prop "$prop" \
    '.issues[$key][$prop] // empty' "$default"
}

# ── Running agent count ─────────────────────────────────────────
autoship_running_count() {
  local workspaces_dir
  workspaces_dir="$(autoship_workspaces_dir 2>/dev/null || true)"
  if [[ -d "${workspaces_dir:-}" ]]; then
    grep -Rsl '^RUNNING$' "$workspaces_dir"/*/status 2>/dev/null | wc -l | tr -d ' '
  else
    printf '0\n'
  fi
}
