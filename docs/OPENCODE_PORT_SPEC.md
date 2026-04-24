# AutoShip OpenCode Port Specification

> **Status:** Draft — Awaiting Implementation  
> **Created:** 2026-04-15  
> **Platform:** OpenCode (macOS/Windows/Linux)  
> **Base:** AutoShip v1.5.0 (OpenCode-first port)

## 1. Overview

This document specifies the port of AutoShip from the legacy Claude Code runtime to OpenCode (Agent-native). The core logic remains identical: autonomous multi-agent GitHub issue → PR pipeline with third-party-first routing, verification pipeline, and quota tracking. The execution layer adapts from tmux panes to OpenCode's built-in `Agent` subagent tool.

**Goal:** Ship every open GitHub issue as a merged PR with minimal human effort.

---

## 2. Key Differences: Legacy Runtime → OpenCode

| Aspect | Legacy Claude runtime | OpenCode (Port) |
|--------|----------------------------|-----------------|
| Agent execution | tmux panes (`tmux new-window`, `tmux send-keys`) | OpenCode `Agent` subagent tool |
| Status detection | `pane.log` + `tmux list-panes -F '#{pane_dead}'` | File-based markers in `.autoship/workspaces/<key>/status` |
| Session lifecycle | tmux session + plugin cache | OpenCode session + state file |
| Monitors | `monitor-agents.sh` (5s), `monitor-prs.sh` (30s), `monitor-issues.sh` (60s) | Polling via skill loops + Bash polling |
| Process management | `tmux kill-pane`, `tmux kill-window` | `Agent` task management via task state |
| Concurrency | Up to 20 tmux panes | Up to 20 concurrent `Agent` subagents |
| Third-party tools | Codex CLI, Gemini CLI, GitHub Copilot | Same CLIs via Bash commands |

---

## 3. Architecture

### 3.1 Four-Tier Model (Preserved)

| Tier | Role | Implementation |
|------|------|----------------|
| **Monitors** | Raw event polling | Bash scripts polling file markers + GitHub API |
| **Triage** | Event interpretation, simple tasks | `haiku-triage` agent (haiku model) |
| **Executor** | Orchestration, dispatch, verification | `autoship-orchestrate` skill (sonnet model) |
| **Advisor** | Strategic decisions | Spawned at trigger points (opus model) |

### 3.2 Data Flow

```
GitHub Issue → orchestrate skill (sonnet)
    ↓
classify-issue.sh → task type
    ↓
dispatch skill → Agent subagent (haiku/sonnet/codex/gemini)
    ↓
Agent writes COMPLETE/BLOCKED/STUCK to status file
    ↓
Monitor detects → event-queue.json
    ↓
verify skill → reviewer agent (sonnet)
    ↓
PR creation → GitHub API
    ↓
Monitor CI → merge
```

---

## 4. Skill Structure

### 4.1 Skill Mapping

| Legacy skill path | OpenCode Skill | Purpose |
|-------------------|----------------|---------|
| `orchestrate/SKILL.md` | `autoship-orchestrate/SKILL.md` | Core orchestration protocol |
| `dispatch/SKILL.md` | `autoship-dispatch/SKILL.md` | Agent dispatch logic |
| `verify/SKILL.md` | `autoship-verify/SKILL.md` | Verification pipeline |
| `status/SKILL.md` | `autoship-status/SKILL.md` | Status dashboard |
| `poll/SKILL.md` | `autoship-poll/SKILL.md` | GitHub issue sync |
| `setup/SKILL.md` | `autoship-setup/SKILL.md` | First-run configuration |
| `discord-webhook/SKILL.md` | `autoship-discord-webhook/SKILL.md` | Discord webhook events |
| `discord-commands/SKILL.md` | `autoship-discord-commands/SKILL.md` | Discord commands |

### 4.2 Skill Location

OpenCode skills are installed via the repo-local bootstrap into `~/.config/opencode/` and then loaded by OpenCode. For this port:

```
AutoShip/
  skills/                    # AutoShip skills (ported)
    autoship-orchestrate/
      SKILL.md
    autoship-dispatch/
      SKILL.md
    autoship-verify/
      SKILL.md
    autoship-status/
      SKILL.md
    autoship-poll/
      SKILL.md
    autoship-setup/
      SKILL.md
    autoship-discord-webhook/
      SKILL.md
    autoship-discord-commands/
      SKILL.md
```

Users install these skills through the repo-local OpenCode bootstrap:
```bash
bash hooks/opencode/install.sh
```

---

## 5. State Management

### 5.1 State Files (`.autoship/`)

All state remains in `.autoship/` in the project root:

| File | Purpose |
|------|---------|
| `state.json` | Issue lifecycle, active agents, plan phases |
| `quota.json` | Per-tool quota percentages |
| `token-ledger.json` | Token usage tracking |
| `config.json` | Project configuration |
| `event-queue.json` | Pending events |
| `routing.json` | Parsed from AUTOSHIP.md |
| `project-context.md` | Extracted conventions |

### 5.2 GitHub Labels (Retained)

Labels persist for durability:
- `autoship:in-progress` — agent working
- `autoship:blocked` — all agents failed
- `autoship:paused` — orchestration halted
- `autoship:done` — completed and merged

### 5.3 Agent Status File

Instead of tmux pane logs, agents write status files:

```
.autoship/workspaces/<issue-key>/
  status          # COMPLETE | BLOCKED | STUCK | RUNNING
  token-count    # integer of tokens used
  AUTOSHIP_RESULT.md  # Agent's structured result
  branch/        # Git branch with changes
```

---

## 6. Dispatch Protocol

### 6.1 Agent Dispatch Flow

```
1. Create worktree: git worktree add .autoship/workspaces/<key> <branch>
2. Determine tool via quota + routing matrix
3. Dispatch via OpenCode Agent subagent:
   - subagent_type: "general" or "explore"
   - model: haiku | sonnet | opus
4. Agent receives prompt with:
   - Full issue context + acceptance criteria
   - Worktree path
   - Instruction to write AUTOSHIP_RESULT.md
   - Instruction to commit all work to git
5. Agent writes status file on completion
6. Monitor detects status file change
7. Orchestrator processes event queue
```

### 6.2 Prompt Structure

```markdown
# Task: Issue #<N> - <title>

## Context
<issue body>

## Acceptance Criteria
- <criterion 1>
- <criterion 2>

## Working Directory
.autoship/workspaces/<issue-key>

## Instructions
1. Create a git branch for this work
2. Implement the changes described above
3. Ensure all acceptance criteria are met
4. Write AUTOSHIP_RESULT.md with:
   - Summary of changes
   - Files modified
   - Acceptance criteria status
   - Any blockers or notes
5. Commit all work to git
6. Write COMPLETE, BLOCKED, or STUCK to the status file

## Project Context
<extracted from .autoship/project-context.md>
```

### 6.3 Third-Party Tool Dispatch

Codex/Gemini dispatched via Bash:

```bash
cd .autoship/workspaces/<key>
<tool> -p "$(cat AUTOSHIP_PROMPT.md)"
```

Completion detected via:
1. Process exit (wait for background job)
2. `AUTOSHIP_RESULT.md` existence check
3. Git diff validation

---

## 7. Monitoring

### 7.1 Monitor Strategy

OpenCode lacks tmux's real-time process monitoring. Instead:

| Monitor | Implementation | Interval |
|---------|----------------|----------|
| Agent status | Poll `.autoship/workspaces/*/status` files | 10s |
| PR CI status | `gh pr view <N> --json statusCheckRollup` | 30s |
| New issues | `gh issue list --state open` diff | 60s |

### 7.2 Monitor Script: `monitor-agents.sh`

```bash
#!/bin/bash
# Poll status files for COMPLETE/BLOCKED/STUCK
for dir in .autoship/workspaces/*/; do
  [ -f "$dir/status" ] || continue
  status=$(cat "$dir/status")
  key=$(basename "$dir")
  case "$status" in
    COMPLETE|BLOCKED|STUCK)
      emit-event.sh "agent_status" "$key" "$status"
      ;;
  esac
done
```

### 7.3 Recovery

If OpenCode session dies:
1. Read `.autoship/state.json`
2. Check worktree git status
3. Resume from last checkpoint

---

## 8. Verification Pipeline

Unchanged from Claude Code version:

```
Agent COMPLETE → verify skill
    ↓
Step 1: REVIEWER (sonnet)
    - Read AUTOSHIP_RESULT.md
    - Read git diff
    - Run test suite
    - Return: PASS | FAIL
    ↓ (FAIL → re-dispatch, max 3 attempts)
    ↓ (PASS → continue)
    ↓
Step 2: SIMPLIFY (sonnet)
    - Create rollback tag
    - Run code simplifier
    ↓
Step 3: RE-VERIFY (sonnet)
    - Confirm simplification preserved correctness
    ↓ (FAIL → revert)
    ↓
Step 4: CREATE PR
    - gh pr create
    ↓
Step 5: MONITOR CI
    - Wait for checks pass
    - Auto-merge
    ↓
Step 6: CLEANUP
    - git worktree remove
    - Close issue
```

---

## 9. Commands

### 9.1 OpenCode Command Format

OpenCode uses slash commands. The following commands will be available:

| Command | Action |
|---------|--------|
| `/autoship` | Show help |
| `/autoship-start` | Launch orchestration |
| `/autoship-stop` | Graceful shutdown |
| `/autoship-plan` | Dry-run analysis |
| `/autoship-status` | Status dashboard |
| `/autoship-setup` | First-run wizard |

### 9.2 Command Implementation

Commands are implemented as skill invocations or direct bash scripts:

```
commands/
  autoship.md         # /autoship (help)
  autoship-start.md   # /autoship-start
  autoship-stop.md    # /autoship-stop
  autoship-plan.md    # /autoship-plan
  autoship-status.md  # /autoship-status
  autoship-setup.md   # /autoship-setup
```

---

## 10. Quota System

### 10.1 Quota Tracking

Preserved exactly from Claude Code version:

| Tool | Quota Source | Decay Model |
|------|--------------|-------------|
| Claude | Max subscription (100%) | N/A |
| Codex Spark | API or decay | -3% per simple dispatch |
| Codex GPT | API or decay | -8% per medium dispatch |
| Gemini | API or decay | -5% per dispatch |
| GitHub Copilot | N/A | Flat allocation |

### 10.2 Routing Matrix (from AUTOSHIP.md)

Unchanged — still reads from `AUTOSHIP.md` YAML front matter:

```yaml
routing:
  research: [gemini, claude-haiku]
  docs: [gemini, claude-haiku]
  simple_code: [codex-spark, gemini]
  medium_code: [codex-gpt, claude-sonnet]
  complex: [claude-sonnet, codex-gpt]
  mechanical: [claude-haiku, gemini]
  ci_fix: [claude-haiku, gemini]
  rust_unsafe: [claude-haiku, claude-sonnet]
```

---

## 11. File Structure

### 11.1 Ported Structure

```
AutoShip/
  plugins/                     # OpenCode plugin entrypoint
  skills/                      # OpenCode skills (ported)
    autoship-orchestrate/
      SKILL.md
    autoship-dispatch/
      SKILL.md
    autoship-verify/
      SKILL.md
    autoship-status/
      SKILL.md
    autoship-poll/
      SKILL.md
    autoship-setup/
      SKILL.md
    autoship-discord-webhook/
      SKILL.md
    autoship-discord-commands/
      SKILL.md
  agents/                      # Agent definitions
    reviewer.md
    haiku-triage.md
  hooks/                       # Bash scripts (ported/adapted)
    init.sh
    detect-tools.sh
    monitor-agents.sh          # Adapted for file polling
    monitor-prs.sh
    monitor-issues.sh
    update-state.sh
    quota-update.sh
    classify-issue.sh
    cleanup-worktree.sh
    emit-event.sh
    extract-context.sh
    sweep-stale.sh
  commands/                    # Slash commands
    autoship.md
    autoship-start.md
    autoship-stop.md
    autoship-plan.md
    autoship-status.md
    autoship-setup.md
  scripts/                     # Utility scripts
    dispatch-codex-appserver.sh
    dispatch-gemini.sh
  docs/
    OPENCODE_PORT_SPEC.md      # This file
    OPENCODE_PORT_PLAN.md      # Implementation plan
  AUTOSHIP.md                  # Routing matrix (unchanged)
  AUTOSHIP_SPEC.md             # Original spec (unchanged)
  AUTOSHIP_ARCHITECTURE.md     # Architecture doc (unchanged)
  README.md                    # Updated with OpenCode section
```

### 11.2 Installation Instructions

```bash
# For OpenCode users:
cp -r AutoShip/skills/* ~/.claude/skills/
cp -r AutoShip/hooks/* ~/.claude/hooks/

# Or for project-local:
cp -r AutoShip/skills/* .claude/skills/
```

---

## 12. Model Configuration

### 12.1 OpenCode Model Variables

| Variable | Purpose | AutoShip Usage |
|----------|---------|----------------|
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Default Opus model | Advisor calls |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Default Sonnet model | Executor + verification |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Default Haiku model | Triage + simple tasks |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Subagent model | Agent dispatch |

### 12.2 Recommended Settings

```yaml
# For AutoShip on OpenCode:
ANTHROPIC_DEFAULT_OPUS_MODEL: claude-opus-4-5
ANTHROPIC_DEFAULT_SONNET_MODEL: claude-sonnet-4-7
ANTHROPIC_DEFAULT_HAIKU_MODEL: claude-haiku-4
CLAUDE_CODE_SUBAGENT_MODEL: sonnet
```

---

## 13. Discord Integration

### 13.1 Webhook Events

Unchanged from Claude Code version. The `autoship-discord-webhook` skill polls Discord for GitHub webhook events and routes to the event queue.

### 13.2 Commands

Unchanged. Responds to:
- "work on #N" → immediate dispatch
- "skip #N" → exclude from plan
- "pause" / "resume" → halt/restart
- "status" → post summary

---

## 14. Testing

### 14.1 Self-Dogfooding

AutoShip will be used to port itself. The plan:
1. Create GitHub issues for port tasks
2. Run `/autoship-start`
3. AutoShip dispatches agents to implement the port
4. Verify and merge

### 14.2 Test Scenarios

| Scenario | Test |
|----------|------|
| Single issue dispatch | Dispatch one issue, verify PR |
| Concurrent dispatch | Dispatch 3+ issues simultaneously |
| Verification failure | Re-dispatch on FAIL |
| Legacy recovery | Kill session, restart, verify state |
| Quota exhaustion | Exhaust third-party quota, verify Claude fallback |
| Third-party tool dispatch | Dispatch to Codex/Gemini |

---

## 15. Implementation Plan Summary

| Task | Description | Priority |
|------|-------------|----------|
| 1 | Core state files + init.sh | P0 |
| 2 | autoship-orchestrate skill | P0 |
| 3 | autoship-dispatch skill | P0 |
| 4 | autoship-verify skill | P0 |
| 5 | autoship-status skill | P1 |
| 6 | autoship-poll skill | P1 |
| 7 | autoship-setup skill | P2 |
| 8 | Discord skills | P2 |
| 9 | Documentation | P2 |

---

## 16. Open Questions

- [ ] Should we support OpenCode's MCP server connections for additional tools?
- [ ] How to handle OpenCode session restarts? (state recovery)
- [ ] Should we use OpenCode's `TeamCreate` for parallel dispatch?
- [ ] Integration with OpenCode's built-in status display vs custom dashboard?

---

*End of specification*
