#!/usr/bin/env bash
set -euo pipefail

# beacon-init.sh — Initialize .beacon/ directory structure and state file.
# Idempotent: safe to re-run without losing existing state.

BEACON_VERSION="0.1.0"

BEACON_DIR=".beacon"
STATE_FILE="$BEACON_DIR/state.json"
WORKSPACES_DIR="$BEACON_DIR/workspaces"

# Resolve the directory this script lives in so we can call sibling scripts.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect repo
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT"

echo "Beacon v${BEACON_VERSION} initializing..."

# Check for jq dependency and minimum version (>= 1.6 required for --argjson)
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: jq not found. Install with: brew install jq" >&2
else
  jq_version=$(jq --version 2>/dev/null | sed 's/jq-//' | cut -d. -f1-2) || jq_version="0.0"
  jq_major=$(echo "$jq_version" | cut -d. -f1)
  jq_minor=$(echo "$jq_version" | cut -d. -f2)
  if (( jq_major < 1 || (jq_major == 1 && jq_minor < 6) )); then
    echo "Warning: jq ${jq_version} found, but >= 1.6 is required. Some features may not work." >&2
  fi
fi

# Check for gh CLI and minimum version (>= 2.0 required for --json flag)
if ! command -v gh >/dev/null 2>&1; then
  echo "Warning: gh not found. Install with: brew install gh && gh auth login" >&2
else
  gh_version=$(gh --version 2>/dev/null | head -1 | awk '{print $3}') || gh_version="0.0.0"
  gh_major=$(echo "$gh_version" | cut -d. -f1)
  if (( gh_major < 2 )); then
    echo "Warning: gh ${gh_version} found, but >= 2.0 is required. Upgrade with: brew upgrade gh" >&2
  fi
fi

# Derive owner/repo from git remote
REPO_SLUG=""
REMOTE_URL=$(git remote get-url origin 2>/dev/null) || true
if [[ -n "$REMOTE_URL" ]]; then
  # Handle both SSH and HTTPS remotes
  REPO_SLUG=$(echo "$REMOTE_URL" | sed -E 's#^.+[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed 's/\.git$//')
fi

# Create directory structure
mkdir -p "$WORKSPACES_DIR"

# Detect tools and parse quotas.
# detect-tools.sh outputs: {"claude": {"available": bool, "quota_pct": N}, ...}
# Transform to state.json format:  {"claude": {"status": "available"|"unavailable", "quota_pct": N}, ...}
TOOLS_RAW=$(bash "$SCRIPT_DIR/detect-tools.sh" 2>/dev/null) || TOOLS_RAW='{}'
TOOLS_JSON=$(printf '%s' "$TOOLS_RAW" | jq '
  to_entries
  | map({
      key: .key,
      value: {
        status: (if .value.available then "available" else "unavailable" end),
        quota_pct: .value.quota_pct
      }
    })
  | from_entries
' 2>/dev/null) || TOOLS_JSON='{
    "claude":     {"status": "available",   "quota_pct": 100},
    "codex-spark":{"status": "unavailable", "quota_pct": -1},
    "codex-gpt":  {"status": "unavailable", "quota_pct": -1},
    "gemini":     {"status": "unavailable", "quota_pct": -1}
  }'

# Initialize quota.json if it doesn't exist (creates decay-tracking file for third-party tools)
if [[ ! -f "$BEACON_DIR/quota.json" ]]; then
  bash "$SCRIPT_DIR/quota-update.sh" init 2>/dev/null || true
fi

# --- Error Recovery #6: Invalid/corrupted state file ---
# If state.json exists but is not valid JSON, back it up and reinitialize.
if [[ -f "$STATE_FILE" ]]; then
  if ! jq '.' "$STATE_FILE" > /dev/null 2>&1; then
    BACKUP="${STATE_FILE}.corrupted.$(date +%s)"
    mv "$STATE_FILE" "$BACKUP"
    echo "State file corrupted — backed up to $BACKUP, initializing fresh" >&2
  fi
fi

# Initialize state.json only if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Use jq to produce well-formed JSON, embedding the detected tools.
  jq -n \
    --arg repo "$REPO_SLUG" \
    --arg now "$NOW" \
    --arg ver "$BEACON_VERSION" \
    --argjson tools "$TOOLS_JSON" \
    '{
      version: 1,
      beacon_version: $ver,
      repo: $repo,
      started_at: $now,
      updated_at: $now,
      plan: {
        phases: [],
        current_phase: 0,
        checkpoint_pending: false
      },
      issues: {},
      tools: $tools,
      stats: {
        dispatched: 0,
        completed: 0,
        failed: 0,
        blocked: 0
      }
    }' > "$STATE_FILE"
  echo "Initialized $STATE_FILE"
else
  # Check for version mismatch and warn (migration notice, non-fatal)
  existing_ver=$(jq -r '.beacon_version // "unknown"' "$STATE_FILE" 2>/dev/null) || existing_ver="unknown"
  if [[ "$existing_ver" != "$BEACON_VERSION" ]]; then
    echo "Notice: state.json has beacon_version=${existing_ver}, current is ${BEACON_VERSION} (migration may be needed)" >&2
  fi

  # Refresh tools section with current quota data without touching other state.
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  UPDATED=$(jq --argjson tools "$TOOLS_JSON" --arg now "$NOW" \
    '.tools = $tools | .updated_at = $now' "$STATE_FILE") && \
    printf '%s\n' "$UPDATED" > "$STATE_FILE"
  echo "Refreshed tools quota in $STATE_FILE"
fi

# Create config.json for operator overrides (if not present)
CONFIG_FILE="$BEACON_DIR/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo '{}' > "$CONFIG_FILE"
  echo "Initialized $CONFIG_FILE (add test_command, etc. for overrides)"
fi

# Create GitHub labels if the repo is on GitHub and gh CLI is available
create_github_labels() {
  # Check if gh CLI is available
  if ! command -v gh &> /dev/null; then
    return 0
  fi

  # Check if we're in a GitHub repo (REPO_SLUG will be set)
  if [[ -z "$REPO_SLUG" ]]; then
    return 0
  fi

  # Create each label if it doesn't exist (bash 3.2 compatible — no associative arrays)
  local pairs="beacon:in-progress=FFEB3B beacon:blocked=F44336 beacon:paused=FF9800 beacon:done=4CAF50"
  for pair in $pairs; do
    label="${pair%%=*}"
    color="${pair#*=}"
    if ! gh label list --repo "$REPO_SLUG" --json name --jq ".[].name" 2>/dev/null | grep -q "^${label}$"; then
      echo "Creating label: $label (color: $color)"
      gh label create "$label" --repo "$REPO_SLUG" --color "$color" --description "Beacon orchestration label" 2>/dev/null || true
    fi
  done
}

# Attempt to create labels (non-fatal if it fails)
create_github_labels || true

# --- Error Recovery #1: Session Restart Reconciliation ---
# If state.json shows issues as running/claimed but the tmux pane is gone,
# reconcile against GitHub labels to decide whether to keep or reset each issue.
reconcile_stale_running() {
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi

  # Collect issue keys that are in running or claimed state
  local stale_keys
  stale_keys=$(jq -r '.issues | to_entries[] | select(.value.state == "running" or .value.state == "claimed") | .key' "$STATE_FILE" 2>/dev/null) || return 0

  if [[ -z "$stale_keys" ]]; then
    return 0
  fi

  echo "Reconciling stale running/claimed issues..."

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue

    # Check if the tmux pane for this issue is still alive
    local pane_id
    pane_id=$(jq -r --arg k "$key" '.issues[$k].pane_id // empty' "$STATE_FILE" 2>/dev/null) || pane_id=""

    local pane_alive=0
    if [[ -n "$pane_id" ]] && command -v tmux >/dev/null 2>&1; then
      if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -q "^${pane_id}$"; then
        pane_alive=1
      fi
    fi

    if [[ $pane_alive -eq 1 ]]; then
      echo "  $key: pane $pane_id still alive — keeping as running"
      continue
    fi

    # Pane is gone. Check GitHub labels as source of truth (if gh available).
    local has_inprogress_label=0
    if [[ -n "$REPO_SLUG" ]] && command -v gh >/dev/null 2>&1; then
      # Extract numeric issue ID from key (e.g. "issue-42" → 42)
      local issue_num="${key#issue-}"
      if gh issue view "$issue_num" --repo "$REPO_SLUG" --json labels \
          --jq '.labels[].name' 2>/dev/null | grep -q "^beacon:in-progress$"; then
        has_inprogress_label=1
      fi
    fi

    # Check worktree directory
    local worktree_path="$WORKSPACES_DIR/$key"
    local worktree_exists=0
    [[ -d "$worktree_path" ]] && worktree_exists=1

    if [[ $has_inprogress_label -eq 1 ]]; then
      # Agent may be running in a different session — preserve state but clear dead pane ref
      echo "  $key: beacon:in-progress label present — preserving running state, clearing pane_id"
      jq --arg k "$key" '.issues[$k].pane_id = null' "$STATE_FILE" > "${STATE_FILE}.tmp" \
        && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
      # No label, no pane → reset to unclaimed
      echo "  $key: no active pane or in-progress label — resetting to unclaimed"
      if [[ $worktree_exists -eq 1 ]]; then
        # Keep worktree/assignment, just reset state
        jq --arg k "$key" \
          '.issues[$k].state = "unclaimed" | .issues[$k].pane_id = null' \
          "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
      else
        # Clear everything
        jq --arg k "$key" \
          '.issues[$k].state = "unclaimed" | .issues[$k].pane_id = null | .issues[$k].worktree = null | .issues[$k].agent = null' \
          "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
      fi
    fi
  done <<< "$stale_keys"
}

reconcile_stale_running || true

# Sweep stale worktrees on startup (non-fatal if it fails)
echo "Scanning for stale worktrees..."
bash "$SCRIPT_DIR/sweep-stale.sh" 2>/dev/null || true

echo "Beacon workspace ready at $BEACON_DIR"
