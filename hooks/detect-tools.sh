#!/usr/bin/env bash
set -euo pipefail

# detect-tools.sh — Detect available AI CLI tools and output JSON report.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT="$(pwd)"
# Outputs quota_pct for each tool: 100 if known-full, -1 if unknown, 0-100 if parseable.
# Always exits 0; missing tools are reported as unavailable, not errors.

# ---------------------------------------------------------------------------
# Quota helpers — return integer 0-100 or -1 (unknown)
# ---------------------------------------------------------------------------

QUOTA_FILE="${REPO_ROOT}/.beacon/quota.json"

# Claude uses a Max subscription — treat as always full.
quota_claude() {
  echo "100"
}

# Read quota from quota.json if it exists; fall back to 100 (optimistic default).
# Returns -1 only if the tool is unavailable (not installed).
_read_quota() {
  local tool="$1"
  if [[ -f "$QUOTA_FILE" ]]; then
    local q
    q=$(jq -r --arg t "$tool" '.[$t].quota_pct // -1' "$QUOTA_FILE" 2>/dev/null)
    echo "${q:--1}"
  else
    echo "100"  # No quota file yet → assume fresh/full
  fi
}

# Codex: no public quota API — use decay-estimated value from quota.json.
quota_codex_spark() { _read_quota "codex-spark"; }
quota_codex_gpt()   { _read_quota "codex-gpt";   }

# Gemini: no quota API — use decay-estimated value from quota.json.
quota_gemini() { _read_quota "gemini"; }

# ---------------------------------------------------------------------------
# Per-tool detection
# ---------------------------------------------------------------------------

detect_claude() {
  if command -v claude >/dev/null 2>&1; then
    local ver qpct
    ver=$(claude --version 2>/dev/null | head -1) || ver="unknown"
    ver=$(printf '%s' "$ver" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    qpct=$(quota_claude)
    printf '"claude": {"available": true, "version": "%s", "quota_pct": %s}' "$ver" "$qpct"
  else
    printf '"claude": {"available": false, "quota_pct": -1}'
  fi
}

detect_codex() {
  if command -v codex >/dev/null 2>&1; then
    local ver spark_q gpt_q
    ver=$(codex --version 2>/dev/null | head -1) || ver="unknown"
    ver=$(printf '%s' "$ver" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    spark_q=$(quota_codex_spark)
    gpt_q=$(quota_codex_gpt)
    printf '"codex-spark": {"available": true, "version": "%s", "quota_pct": %s}, ' \
      "$ver" "$spark_q"
    printf '"codex-gpt": {"available": true, "version": "%s", "quota_pct": %s}' \
      "$ver" "$gpt_q"
  else
    printf '"codex-spark": {"available": false, "quota_pct": -1}, '
    printf '"codex-gpt": {"available": false, "quota_pct": -1}'
  fi
}

detect_gemini() {
  if command -v gemini >/dev/null 2>&1; then
    local ver qpct
    ver=$(gemini --version 2>/dev/null | head -1) || ver="unknown"
    ver=$(printf '%s' "$ver" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    qpct=$(quota_gemini)
    printf '"gemini": {"available": true, "version": "%s", "quota_pct": %s}' "$ver" "$qpct"
  else
    printf '"gemini": {"available": false, "quota_pct": -1}'
  fi
}

# ---------------------------------------------------------------------------
# Build JSON output
# ---------------------------------------------------------------------------

echo -n "{"
detect_claude
echo -n ", "
detect_codex
echo -n ", "
detect_gemini
echo "}"

exit 0
