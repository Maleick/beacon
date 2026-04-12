---
name: beacon-status
description: Display current Beacon orchestration status — running agents, quota, progress, and issue states
tools: ["Bash", "Read"]
---

# Beacon Status

Display the current state of the Beacon orchestration session.

## Process

1. Read `.beacon/state.json` for tracked state.
2. Query tmux for active panes: `tmux list-panes -t beacon -F '#{pane_id} #{pane_title} #{pane_dead}'`
3. Summarize:
   - Active agents (tool, issue, duration)
   - Quota per tool
   - Issues: unclaimed, running, completed, blocked
   - Current phase and checkpoint status

## Output Format

```
BEACON STATUS
─────────────
Repo: owner/repo
Uptime: Xh Ym
Phase: 2/4 (checkpoint pending: no)

AGENTS (3 active / 20 max)
  [Sonnet] #42 — Fix login validation     (12m)
  [Codex]  #45 — Add rate limiting         (8m)
  [Gemini] #48 — Update docs              (3m)

QUOTA
  Claude:      ████████████████████ available
  Codex Spark: ████████░░░░░░░░░░░░ ~40%
  Codex GPT:   ██████████████░░░░░░ ~70%
  Gemini:      ██████░░░░░░░░░░░░░░ ~30%

PROGRESS
  Dispatched: 12  Completed: 8  Failed: 1  Blocked: 0
  PRs open: 3  PRs merged: 5
```
