#!/usr/bin/env bash
# supervisor-loop.sh — keep AutoShip moving from status changes to capacity refill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  source "$SCRIPT_DIR/lib/common.sh"
else
  autoship_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
  }
fi

REPO_ROOT="$(autoship_repo_root)"
cd "$REPO_ROOT"

AUTOSHIP_DIR=".autoship"
WORKSPACES_DIR="$AUTOSHIP_DIR/workspaces"
LOCK_FILE="$AUTOSHIP_DIR/supervisor-loop.lock"
LOG_FILE="$AUTOSHIP_DIR/logs/supervisor-loop.log"
INTERVAL_SECONDS="${AUTOSHIP_SUPERVISOR_INTERVAL_SECONDS:-30}"
ONCE=false
DAEMON=false
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Usage: supervisor-loop.sh [--once] [--daemon] [--interval SECONDS]

Runs AutoShip supervision passes:
  monitor agents -> process event queue -> reconcile state -> runner refill
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      ONCE=true
      shift
      ;;
    --daemon)
      DAEMON=true
      shift
      ;;
    --interval)
      INTERVAL_SECONDS="${2:?--interval requires seconds}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || ((INTERVAL_SECONDS < 1)); then
  INTERVAL_SECONDS=30
fi

mkdir -p "$AUTOSHIP_DIR/logs"

log_supervisor() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG_FILE"
}

status_of() {
  local status_file="$1/status"
  [[ -f "$status_file" ]] || return 1
  tr -d '[:space:]' <"$status_file" 2>/dev/null || true
}

pid_matches_command() {
  local pid="$1" expected_file="$2"
  [[ -s "$expected_file" ]] || return 1
  local expected current
  expected=$(cat "$expected_file" 2>/dev/null || true)
  current=$(ps -p "$pid" -o command= 2>/dev/null || true)
  [[ -n "$current" && "$current" == "$expected" ]]
}

worker_is_live() {
  local dir="$1" pid_file="$1/worker.pid" pid
  [[ -s "$pid_file" ]] || return 1
  pid=$(tr -d '[:space:]' <"$pid_file")
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  pid_matches_command "$pid" "$dir/worker.command"
}

has_fresh_result() {
  local dir="$1" result_file started_file="$1/started_at"
  for result_file in "$dir/AUTOSHIP_RESULT.md" "$dir/HERMES_RESULT.md"; do
    [[ -s "$result_file" ]] || continue
    [[ ! -f "$started_file" || "$result_file" -nt "$started_file" ]] && return 0
  done
  return 1
}

clear_stale_running_workspaces() {
  [[ -d "$WORKSPACES_DIR" ]] || return 0
  local dir issue status
  for dir in "$WORKSPACES_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    issue=$(basename "$dir")
    [[ "$issue" =~ ^issue-[0-9]+$ ]] || continue
    status=$(status_of "$dir")
    [[ "$status" == "RUNNING" ]] || continue
    if ! worker_is_live "$dir"; then
      if has_fresh_result "$dir"; then
        printf 'COMPLETE\n' >"$dir/status"
        log_supervisor "marked stale running workspace complete issue=$issue"
      else
        printf 'STUCK\n' >"$dir/status"
        log_supervisor "marked stale running workspace stuck issue=$issue"
      fi
    fi
  done
}

run_hook_if_present() {
  local hook="$1"
  if [[ -x "$SCRIPT_DIR/$hook" ]]; then
    bash "$SCRIPT_DIR/$hook"
  elif [[ -f "$SCRIPT_DIR/$hook" ]]; then
    bash "$SCRIPT_DIR/$hook"
  fi
}

supervisor_pass() {
  log_supervisor "pass started"
  run_hook_if_present monitor-agents.sh
  clear_stale_running_workspaces
  run_hook_if_present process-event-queue.sh
  run_hook_if_present reconcile-state.sh
  run_hook_if_present runner.sh
  log_supervisor "pass finished"
}

run_loop() {
  while true; do
    supervisor_pass
    [[ "$ONCE" == "true" ]] && break
    sleep "$INTERVAL_SECONDS"
  done
}

with_lock() {
  mkdir -p "$AUTOSHIP_DIR"
  if [[ -L "$LOCK_FILE" ]]; then
    echo "Error: refusing symlink supervisor lock: $LOCK_FILE" >&2
    exit 1
  fi
  touch "$LOCK_FILE"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] && command -v lockf >/dev/null 2>&1; then
    if [[ -z "${AUTOSHIP_SUPERVISOR_LOCKED:-}" ]]; then
      export AUTOSHIP_SUPERVISOR_LOCKED=1
      exec lockf -k "$LOCK_FILE" "$0" "${ORIGINAL_ARGS[@]}"
    fi
  elif command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -x 9
  elif command -v lockf >/dev/null 2>&1; then
    if [[ -z "${AUTOSHIP_SUPERVISOR_LOCKED:-}" ]]; then
      export AUTOSHIP_SUPERVISOR_LOCKED=1
      exec lockf -k "$LOCK_FILE" "$0" "${ORIGINAL_ARGS[@]}"
    fi
  else
    local lock_dir="$LOCK_FILE.d"
    if ! mkdir "$lock_dir" 2>/dev/null; then
      log_supervisor "supervisor already running lock=$lock_dir"
      exit 0
    fi
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM
  fi
  run_loop
}

if [[ "$DAEMON" == "true" && "$ONCE" != "true" ]]; then
  log_supervisor "daemon started interval=${INTERVAL_SECONDS}s"
fi

with_lock "$@"
