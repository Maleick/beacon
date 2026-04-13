# Result: #52 — exhaustion gate

## Status: DONE

## Changes Made
- skills/beacon-dispatch/SKILL.md: Added "Step 2B: Pre-Dispatch Exhaustion Gate" section between Step 2 and Step 3A. Includes bash snippet that checks `exhausted` flag per agent in `.beacon/quota.json`, iterates through the priority list skipping exhausted agents, selects first available agent, and re-runs `hooks/detect-tools.sh` every 5 dispatches to refresh quota estimates. Also added fallback BLOCKED escalation when all agents are exhausted.

## Tests
- Command: `grep -c 'exhausted' skills/beacon-dispatch/SKILL.md`
- Result: PASS (9 matches)

## Notes
- Exhaustion gate placed as Step 2B — runs after worktree/pane setup, before agent-specific dispatch steps (3A/3B/3C)
- detect-tools.sh refresh fires on dispatch_count % 5 == 0 (and > 0) to avoid running on first dispatch
- If all agents exhausted: issue marked BLOCKED, escalates to Opus advisor
