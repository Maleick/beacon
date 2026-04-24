# init-opencode.sh — Initialize .autoship/ directory for OpenCode
# Adapted from init.sh for OpenCode's Agent-based execution

set -euo pipefail

AUTOSHIP_VERSION="1.5.0-opencode"
AUTOSHIP_DIR=".autoship"
STATE_FILE="$AUTOSHIP_DIR/state.json"
WORKSPACES_DIR="$AUTOSHIP_DIR/workspaces"
LEDGER_FILE="$AUTOSHIP_DIR/token-ledger.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT"

echo "AutoShip v${AUTOSHIP_VERSION} initializing for OpenCode..."

bash "$SCRIPT_DIR/sync-release.sh"

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: jq not found. Install with: brew install jq" >&2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Warning: gh not found. Install with: brew install gh" >&2
fi

# Derive repo from git remote
REPO_SLUG=""
REMOTE_URL=$(git remote get-url origin 2>/dev/null) || true
if [[ -n "$REMOTE_URL" ]]; then
  REPO_SLUG=$(echo "$REMOTE_URL" | sed -E 's#^.+[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed 's/\.git$//')
fi

# Create directory structure
mkdir -p "$WORKSPACES_DIR"
mkdir -p "$AUTOSHIP_DIR/results"

# Initialize files
[[ ! -f "$AUTOSHIP_DIR/event-queue.json" ]] && echo '[]' > "$AUTOSHIP_DIR/event-queue.json"
[[ ! -f "$AUTOSHIP_DIR/.pr-monitor-seen.json" ]] && echo '{}' > "$AUTOSHIP_DIR/.pr-monitor-seen.json"
[[ ! -f "$AUTOSHIP_DIR/quota.json" ]] && bash "$SCRIPT_DIR/quota-update.sh" init 2>/dev/null || true
[[ ! -f "$AUTOSHIP_DIR/config.json" ]] && echo '{}' > "$AUTOSHIP_DIR/config.json"

# Initialize state.json
if [[ ! -f "$STATE_FILE" ]]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --arg repo "$REPO_SLUG" \
    --arg now "$NOW" \
    --arg ver "$AUTOSHIP_VERSION" \
    '{
      version: 1,
      autoship_version: $ver,
      platform: "opencode",
      repo: $repo,
      started_at: $now,
      updated_at: $now,
      paused: false,
      plan: {
        phases: [],
        current_phase: 0,
        checkpoint_pending: false
      },
      issues: {},
      tools: {
        "claude-haiku": {"status": "available", "quota_pct": 100},
        "claude-sonnet": {"status": "available", "quota_pct": 100},
        "claude-opus": {"status": "available", "quota_pct": 100},
        "codex-spark": {"status": "unavailable", "quota_pct": -1},
        "codex-gpt": {"status": "unavailable", "quota_pct": -1},
        "gemini": {"status": "unavailable", "quota_pct": -1}
      },
      stats: {
        session_dispatched: 0,
        session_completed: 0,
        total_dispatched_all_time: 0,
        total_completed_all_time: 0,
        failed: 0,
        blocked: 0
      }
    }' > "$STATE_FILE"
  echo "Initialized $STATE_FILE"
else
  # Refresh tools and reset session counters
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "$NOW" \
    '.updated_at = $now |
     .stats.session_dispatched = 0 |
     .stats.session_completed = 0 |
     .platform = "opencode"' \
    "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo "Refreshed $STATE_FILE"
fi

# Detect tools for OpenCode
DETECTED_TOOLS="{}"
if command -v codex >/dev/null 2>&1; then
  DETECTED_TOOLS=$(jq '.codex = {"available": true}' <<< "$DETECTED_TOOLS")
fi
if command -v gemini >/dev/null 2>&1; then
  DETECTED_TOOLS=$(jq '.gemini = {"available": true}' <<< "$DETECTED_TOOLS")
fi

# Update tools in state
jq --argjson tools "$DETECTED_TOOLS" \
  '.tools["codex-spark"].status = (if $tools.codex.available == true then "available" else "unavailable" end) |
   .tools["codex-gpt"].status = (if $tools.codex.available == true then "available" else "unavailable" end) |
   .tools["gemini"].status = (if $tools.gemini.available == true then "available" else "unavailable" end)' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

# Initialize token ledger
init_token_ledger() {
  if ! command -v jq >/dev/null 2>&1; then return 0; fi
  local now session_id
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  session_id="session-$(date -u +%s)-$$"
  local new_session
  new_session=$(jq -n \
    --arg sid "$session_id" \
    --arg now "$now" \
    --arg repo "$REPO_SLUG" \
    '{session_id: $sid, started_at: $now, repo: $repo, issues: []}')
  if [[ -f "$LEDGER_FILE" ]]; then
    jq --argjson s "$new_session" '.sessions += [$s]' "$LEDGER_FILE" > "$LEDGER_FILE.tmp" && mv "$LEDGER_FILE.tmp" "$LEDGER_FILE"
  else
    jq -n --argjson s "$new_session" '{schema_version: 1, sessions: [$s]}' > "$LEDGER_FILE"
  fi
  echo "Token ledger updated: session $session_id"
}
init_token_ledger

# Create GitHub labels
if command -v gh >/dev/null 2>&1 && [[ -n "$REPO_SLUG" ]]; then
  for pair in "autoship:in-progress=FFEB3B" "autoship:blocked=F44336" "autoship:paused=FF9800" "autoship:done=4CAF50"; do
    label="${pair%%=*}"
    color="${pair#*=}"
    gh label create "$label" --repo "$REPO_SLUG" --color "$color" --description "AutoShip" 2>/dev/null || true
  done
fi

# Load routing config
load_routing_config() {
  local routing_file="$AUTOSHIP_DIR/routing.json"
  local autoship_md="AUTOSHIP.md"
  local DEFAULT_ROUTING='{"routing":{"research":["gemini","claude-haiku"],"docs":["gemini","claude-haiku"],"simple_code":["codex-spark","gemini","claude-haiku"],"medium_code":["codex-gpt","claude-sonnet"],"complex":["claude-sonnet"],"mechanical":["claude-haiku","gemini"],"ci_fix":["claude-haiku","gemini"],"rust_unsafe":["claude-haiku","claude-sonnet"]},"max_concurrent_agents":20}'
  if [[ ! -f "$autoship_md" ]]; then
    printf '%s\n' "$DEFAULT_ROUTING" > "$routing_file"
    return 0
  fi
  # Simple YAML front matter extraction
  local front_matter
  front_matter=$(awk '/^---$/{if(p){exit}else{p=1;next}} p{print}' "$autoship_md" 2>/dev/null) || front_matter=""
  if [[ -z "$front_matter" ]]; then
    printf '%s\n' "$DEFAULT_ROUTING" > "$routing_file"
    return 0
  fi
  # Parse and validate (simplified for OpenCode)
  printf '%s\n' "$DEFAULT_ROUTING" > "$routing_file"
}
load_routing_config

# Write the repo hooks directory so shared hooks can resolve sibling scripts.
echo "$REPO_ROOT/hooks" > "$AUTOSHIP_DIR/hooks_dir"

# Sweep stale worktrees
echo "Scanning for stale worktrees..."
bash "$REPO_ROOT/hooks/sweep-stale.sh" 2>/dev/null || true

echo "AutoShip OpenCode workspace ready at $AUTOSHIP_DIR"
