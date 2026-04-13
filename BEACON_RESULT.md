# Result: #42 — Gemini Symphony shim

## Status: DONE

## Changes Made
- hooks/shims/gemini-appserver.sh: created

## Tests
- Command: `test -x hooks/shims/gemini-appserver.sh && echo PASS`
- Result: PASS
- Command: `bash -n hooks/shims/gemini-appserver.sh && echo "syntax OK"`
- Result: syntax OK

## Notes
- Follows grok-appserver.sh pattern exactly
- Handles Symphony turn/start format with `input[0].text` extraction (issue requirement), plus `.prompt`/`.content`/`.text` fallbacks
- Stall timeout: 300s watchdog kills gemini subprocess, emits turn/failed with descriptive message
- Token parsing: greps gemini output for "Total tokens: N", "tokens: N", or "tokenCount: N" patterns; falls back to 0
- turn/failed event used for non-zero exits (matching issue spec), turn/completed for exit 0
- threadId fixed to "beacon-gemini" per spec
- Script is executable (chmod +x applied)
