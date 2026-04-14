#!/usr/bin/env bash
# setup.sh — First-run configuration: model selection, API key storage, concurrency tuning
# Called by activate.sh if .autoship/.onboarded is missing

set -euo pipefail

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT" || exit 1

# Ensure .autoship exists
mkdir -p .autoship

# Invoke the setup skill — prompts user for model config, API keys, concurrency
# The skill writes to ~/.claude/settings.json and ~/.claude/.secrets/
# Then this script updates .autoship/state.json and .autoship/routing.json

echo "=== AutoShip First-Run Setup ==="
echo ""
echo "This wizard will configure:"
echo "  1. Model selection (Lean/Balanced/Maxed)"
echo "  2. API key management (OpenAI, Gemini)"
echo "  3. Agent concurrency limits"
echo ""

# Detect jq
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required. Install: brew install jq"
  exit 1
fi

# Detect gh
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh required. Install: brew install gh"
  exit 1
fi

# Read current config or defaults
SETTINGS="${HOME}/.claude/settings.json"
MODEL_CONFIG=$(jq -r '.env.AUTOSHIP_MODEL_CONFIG // "lean"' "$SETTINGS" 2>/dev/null || echo "lean")
MAX_AGENTS=$(jq -r '.env.AUTOSHIP_MAX_AGENTS // "10"' "$SETTINGS" 2>/dev/null || echo "10")

echo "Current config:"
echo "  Model config: $MODEL_CONFIG"
echo "  Max agents: $MAX_AGENTS"
echo ""

# If user wants to reconfigure, they can manually edit ~/.claude/settings.json
# or delete .autoship/.onboarded and re-run /autoship:setup

# Detect available tools
echo "Detecting available tools..."
TOOLS=$(bash "$REPO_ROOT/hooks/detect-tools.sh" 2>/dev/null || echo '{}')

CLAUDE_AVAILABLE=$(echo "$TOOLS" | jq -r '.["claude-haiku"].available // false' 2>/dev/null || echo "false")
SONNET_AVAILABLE=$(echo "$TOOLS" | jq -r '.["claude-sonnet"].available // false' 2>/dev/null || echo "false")
OPUS_AVAILABLE=$(echo "$TOOLS" | jq -r '.["claude-opus"].available // false' 2>/dev/null || echo "false")
CODEX_AVAILABLE=$(echo "$TOOLS" | jq -r '.["codex-spark"].available // false' 2>/dev/null || echo "false")
GEMINI_AVAILABLE=$(echo "$TOOLS" | jq -r '.["gemini"].available // false' 2>/dev/null || echo "false")

echo "Tools:"
echo "  Claude Haiku:  $CLAUDE_AVAILABLE"
echo "  Claude Sonnet: $SONNET_AVAILABLE"
echo "  Claude Opus:   $OPUS_AVAILABLE"
echo "  Codex:         $CODEX_AVAILABLE"
echo "  Gemini:        $GEMINI_AVAILABLE"
echo ""

# Mark as onboarded
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$DATE" > .autoship/.onboarded
echo "✓ Setup complete. Saved to .autoship/.onboarded"
echo ""
echo "To reconfigure, run: rm .autoship/.onboarded && /autoship:setup"
