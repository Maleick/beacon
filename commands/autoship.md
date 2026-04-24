---
name: autoship
description: Start AutoShip orchestration — reads GitHub issues, dispatches agents, verifies, creates PRs, and merges
platform: opencode
trigger:
  - "start autoship"
  - "run autoship"
  - "autoship start"
  - "/autoship"
---

# AutoShip — Autonomous GitHub Issue → PR Pipeline

AutoShip reads open GitHub issues, dispatches AI agents to implement them, verifies the work, and auto-merges successful PRs.

## Quick Start

```
Run: /autoship
```

## What It Does

1. **Reads** open GitHub issues
2. **Classifies** each by complexity (simple/medium/complex)
3. **Dispatches** agents (Claude Haiku, Sonnet, Codex, Gemini)
4. **Verifies** work against acceptance criteria
5. **Creates** pull requests
6. **Monitors** CI
7. **Merges** when CI passes

## Available Commands

| Command | Description |
|---------|-------------|
| `/autoship` | Start orchestration |
| `/autoship-status` | Show current status |
| `/autoship-plan` | Dry-run (show plan without executing) |
| `/autoship-setup` | First-run configuration |
| `/autoship-stop` | Gracefully stop |

## Requirements

- `gh` CLI authenticated (`gh auth login`)
- Git repo with GitHub remote
- Open issues to work on

## Optional Tools

- `codex` — For simple/medium tasks (burns OpenAI quota first)
- `gemini` — For simple/medium tasks (burns Google AI quota first)

## How It Works

```
Issue → Classify → Dispatch Agent → Verify → PR → CI → Merge
         ↓
    Routing by complexity + quota
```

## Third-Party First

AutoShip burns Codex/Gemini quota before Claude:
- Simple: Codex → Gemini → Haiku
- Medium: Codex → Sonnet
- Complex: Sonnet (always Claude)

## Token Budget

Quotas tracked in `.autoship/quota.json`. Third-party tools exhausted first to preserve Claude budget.

## State Files

- `.autoship/state.json` — Issue lifecycle
- `.autoship/quota.json` — Tool quotas
- `.autoship/token-ledger.json` — Token usage
- `.autoship/event-queue.json` — Pending events
