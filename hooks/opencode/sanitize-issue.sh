#!/usr/bin/env bash
set -euo pipefail

SANITIZE_LOG="${SANITIZE_LOG:-.autoship/sanitize.log}"
SANITIZE_MAX_BODY_SIZE="${SANITIZE_MAX_BODY_SIZE:-8192}"
SANITIZE_DRY_RUN="${SANITIZE_DRY_RUN:-false}"

readonly SANITIZE_MAX_BODY_SIZE

log_flagged() {
  local issue_num="$1"
  local pattern="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] issue=$issue_num pattern='$pattern'" >>"$SANITIZE_LOG"
}

neutralize_prompt_markers() {
  local text="$1"
  local pattern
  local inj_patterns=(
    'system:' 'assistant:' 'model:' 'developer message'
    'tool call' 'ignore previous' 'ignore all' 'exfiltrate'
    'print env' 'environment variables' 'secret' 'token'
    '<<SYS>>' '<</sys>>' '<<INST>>' '<</INST>>'
    '<<USER>>' '<</USER>>' '<</AUTO>>'
  )

  for pattern in "${inj_patterns[@]}"; do
    text=$(
      PATTERN="$pattern" TEXT="$text" python3 - <<'PY'
import os
import re

pattern = os.environ["PATTERN"]
text = os.environ["TEXT"]
print(re.sub(re.escape(pattern), "[PROMPT_MARKER_REMOVED]", text, flags=re.IGNORECASE), end="")
PY
    )
  done
  printf '%s' "$text"
}

sanitize_issue_body() {
  local issue_num="$1"
  local body="$2"

  local original_len=${#body}
  local sanitized="$body"

  log_flagged "$issue_num" "check_start"

  if [[ $original_len -gt $SANITIZE_MAX_BODY_SIZE ]]; then
    sanitized="${body:0:$SANITIZE_MAX_BODY_SIZE}"
    sanitized+=$'\n\n[... truncated: original was $original_len bytes, exceeded SANITIZE_MAX_BODY_SIZE limit]'
    log_flagged "$issue_num" "size_truncation"
  fi

  sanitized=$(neutralize_prompt_markers "$sanitized")

  if LC_ALL=C grep -q '[^[:print:][:space:]]' <<<"$sanitized"; then
    log_flagged "$issue_num" "control_characters"
    sanitized=$(echo "$sanitized" | tr -cd '[:print:]\n\t' || true)
  fi

  sanitized=${sanitized//<<<USER_ISSUE_BODY>>>/[USER_ISSUE_BODY_DELIMITER_REMOVED]}
  sanitized=${sanitized//<<<END_USER_ISSUE_BODY>>>/[USER_ISSUE_BODY_DELIMITER_REMOVED]}

  local base64_pattern='[A-Za-z0-9+/]{100,}={0,2}'
  if echo "$sanitized" | grep -P "$base64_pattern" >/dev/null 2>&1; then
    log_flagged "$issue_num" "base64_like"
  fi

  if [[ "$SANITIZE_DRY_RUN" == "false" ]]; then
    printf '%s' "$sanitized"
  else
    printf '%s' "$body"
  fi
}

sanitize_issue_field() {
  local field="$1"
  field=${field//$'\r'/ }
  field=${field//$'\n'/ }
  field=${field:0:512}
  field=${field//<<<USER_ISSUE_BODY>>>/[USER_ISSUE_BODY_DELIMITER_REMOVED]}
  field=${field//<<<END_USER_ISSUE_BODY>>>/[USER_ISSUE_BODY_DELIMITER_REMOVED]}
  field=$(neutralize_prompt_markers "$field")
  printf '%s' "$field"
}

wrap_issue_body() {
  local body="$1"
  printf '<<<USER_ISSUE_BODY>>>\n%s\n<<<END_USER_ISSUE_BODY>>>' "$body"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  COMMAND="${1:-}"
  shift || true

  case "$COMMAND" in
    sanitize)
      ISSUE_NUM="${1:-}" BODY="${2:-}"
      if [[ -z "$ISSUE_NUM" || -z "$BODY" ]]; then
        echo "Usage: $0 sanitize <issue-num> <body>" >&2
        exit 1
      fi
      sanitize_issue_body "$ISSUE_NUM" "$BODY"
      ;;
    wrap)
      BODY="${1:-}"
      if [[ -z "$BODY" ]]; then
        echo "Usage: $0 wrap <body>" >&2
        exit 1
      fi
      wrap_issue_body "$BODY"
      ;;
    check)
      ISSUE_NUM="${1:-}" BODY="${2:-}"
      if [[ -z "$ISSUE_NUM" || -z "$BODY" ]]; then
        echo "Usage: $0 check <issue-num> <body>" >&2
        exit 1
      fi
      SANITIZE_DRY_RUN=true sanitize_issue_body "$ISSUE_NUM" "$BODY"
      ;;
    *)
      echo "Usage: $0 <command> [args...]" >&2
      echo "Commands:" >&2
      echo "  sanitize <issue-num> <body>  - Sanitize and output body" >&2
      echo "  wrap <body>             - Wrap body in delimiters" >&2
      echo "  check <issue-num> <body> - Check but don't modify" >&2
      exit 1
      ;;
  esac
fi
