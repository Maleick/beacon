---
name: autoship-plan
description: Dry-run AutoShip — analyze issues and show dispatch plan without executing
platform: opencode
---

# /autoship-plan — Dry Run

Analyze open GitHub issues and show the dispatch plan without executing.

## Fetch Open Issues

```bash
gh issue list --state open --json number,title,body,labels --limit 200
```

## Classify Each Issue

```bash
for issue in $(gh issue list --state open --json number --jq '.[].number'); do
  bash hooks/classify-issue.sh "$issue"
done
```

## Build Plan

For each issue:
1. Complexity (simple/medium/complex)
2. Assigned tool based on routing matrix
3. Dependencies (blocks: #N, depends-on: #N)

## Display Plan

```
═══════════════════════════════════════════
           AUTOSHIP DISPATCH PLAN
═══════════════════════════════════════════

Phase 1 (3 issues)
───────────────────────────────────────────
  #42  simple_code    → Codex/Haiku
  #45  medium_code     → Codex/Sonnet
  #48  docs           → Gemini

Phase 2 (2 issues)
───────────────────────────────────────────
  #51  complex         → Sonnet + Opus advisor
  #53  ci_fix          → Haiku

Blocked (1 issue)
───────────────────────────────────────────
  #39  blocked by #42

═══════════════════════════════════════════
Quota Estimate
───────────────────────────────────────────
  Codex:   ~40% remaining
  Gemini:  ~30% remaining
  Claude:  Claude Max (unlimited)

Total: 6 issues across 2 phases
═══════════════════════════════════════════
```

## No Execution

This command only reads and analyzes. No agents are dispatched, no changes made.
