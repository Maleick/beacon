---
name: beacon-status
description: Display current Beacon orchestration status — running agents, quota, progress, and issue states
tools: ["Bash", "Read"]
---

# Beacon Status

Display the current state of the Beacon orchestration session.

## Process

### Step 1: Read State File

```bash
cat .beacon/state.json 2>/dev/null
```

**If file is missing**: Display "No active Beacon session. Run `/beacon start` to begin." and stop.

**If file is corrupted** (invalid JSON): Display error and suggest recovery:

```
BEACON STATUS: ERROR
State file corrupted. Recovery options:
  1. Run `/beacon start` to rebuild state from GitHub labels
  2. Delete .beacon/state.json and restart
```

### Step 2: Query Tmux

```bash
tmux list-panes -t beacon -F '#{pane_id} #{pane_title} #{pane_dead} #{pane_start_command}' 2>/dev/null
```

**If tmux session doesn't exist**: Note "tmux session 'beacon' not found" — agents may have died. Show state file data only.

### Step 3: Reconcile

Cross-reference state file entries with tmux panes:

- State says "running" but pane is dead → flag as "completed (unchecked)" or "crashed"
- Pane exists but no state entry → flag as "orphaned pane"

### Step 4: Render Output

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

### Quota Bar Rendering

Each bar is exactly 20 characters wide. Calculate filled blocks:

```
filled = round(quota_pct / 5)  # 100% = 20 blocks, 50% = 10 blocks
bar = "█" * filled + "░" * (20 - filled)
```

Color hints (for terminal output):

- `> 50%`: show as "available" or exact percentage
- `10-50%`: show as "~N%" (warning zone)
- `< 10%`: show as "LOW" (dispatch will skip this tool)
- `0%`: show as "EXHAUSTED"

### When No Agents Are Running

```
BEACON STATUS
─────────────
Repo: owner/repo
Uptime: Xh Ym
Phase: 3/4 (checkpoint pending: yes)

AGENTS (0 active / 20 max)
  No agents currently running.
  Next phase waiting on checkpoint review.

QUOTA
  <same format>

PROGRESS
  Dispatched: 12  Completed: 12  Failed: 0  Blocked: 0
  PRs open: 0  PRs merged: 12
  All issues in current phase complete. Run checkpoint to continue.
```
