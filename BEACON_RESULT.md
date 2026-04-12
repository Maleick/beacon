# Result: #25 — Add jq dependency check to beacon-init.sh

## Status: DONE

## Changes Made

- `hooks/beacon-init.sh`: Added jq dependency check after git repository detection. The check prints a clear warning message if jq is not found: "Warning: jq not found. Install with: brew install jq". The script continues to execute successfully (jq is needed later in other hook scripts, not during init).

- `CLAUDE.md`: Added a new "Prerequisites" section documenting that jq is required for state updates and completion tracking. Includes installation instructions for macOS via Homebrew.

## Tests

- Test command: `none (markdown/bash plugin)`
- Result: N/A
- New tests added: no

## Notes

The jq check is non-blocking — beacon-init.sh will still succeed even if jq is missing. This is appropriate because:
1. The init script itself doesn't use jq (it writes the initial JSON directly)
2. jq is only required by downstream hooks like update-state.sh and optionally by check-completion.sh
3. An early warning at init time helps users catch the missing dependency before running beacon commands that depend on it

The check uses `command -v jq >/dev/null 2>&1` which is a portable way to detect if jq is available in the PATH.
