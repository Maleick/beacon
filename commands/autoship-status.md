---
name: autoship-status
description: Show AutoShip orchestration status
platform: opencode
---

# /autoship-status — Status Dashboard

Display current AutoShip orchestration status.

## Run Status Skill

Invoke the `autoship-status` skill which reads:
- `.autoship/state.json` — issue states, stats
- `.autoship/quota.json` — tool quotas
- `.autoship/token-ledger.json` — token usage
- GitHub PR counts

## Output

```
═══════════════════════════════════════════
              AUTOSHIP STATUS
═══════════════════════════════════════════
Repo:         owner/repo
Uptime:       Xh Ym
Phase:        N/M

───────────────────────────────────────────
AGENTS (N active / 20 max)
───────────────────────────────────────────
  [Haiku]   #42 — Fix login validation
  [Sonnet]  #45 — Add rate limiting
  ...

───────────────────────────────────────────
QUOTA
───────────────────────────────────────────
  Claude:   Claude Max — N dispatches
  Codex:    ████████░░░░░░░░░░░░ ~40%
  Gemini:   ██████░░░░░░░░░░░░░ ~30%

───────────────────────────────────────────
PROGRESS
───────────────────────────────────────────
  Session:   Dispatched: N   Completed: N
  PRs open:  N   PRs merged: N
═══════════════════════════════════════════
```

## No Session

If no active session:
```
No active AutoShip session.
Run /autoship to start.
```
