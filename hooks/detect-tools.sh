#!/usr/bin/env bash
set -euo pipefail

# detect-tools.sh — Detect available AI CLI tools and output JSON report.
# Always exits 0; missing tools are reported as unavailable, not errors.

detect_tool() {
  local name="$1"
  local cmd="$2"
  local version_flag="${3:---version}"

  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver=$("$cmd" "$version_flag" 2>/dev/null | head -1) || ver="unknown"
    # Escape version string for safe JSON embedding
    ver=$(printf '%s' "$ver" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    printf '"%s": {"available": true, "version": "%s"}' "$name" "$ver"
  else
    printf '"%s": {"available": false}' "$name"
  fi
}

# Build JSON output
echo -n "{"
detect_tool "claude" "claude" "--version"
echo -n ", "
detect_tool "codex" "codex" "--version"
echo -n ", "
detect_tool "gemini" "gemini" "--version"
echo "}"

exit 0
