# Beacon

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://claude.ai/code)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)]()
[![Status](https://img.shields.io/badge/status-development-orange)]()

**Autonomous multi-agent orchestration for Claude Code.**

Beacon reads GitHub Issues, routes work to the best available AI CLI tool (Claude, Codex, or Gemini), verifies results, and auto-merges approved work — all orchestrated by Claude Opus in tmux.

## How It Works

```
GitHub Issues → Opus Orchestrator → Agent Dispatch → Verification → PR → Auto-Merge
                     │                    │
                     │              ┌─────┴──────┐
                     │              │             │
                UltraPlan      TeamCreate    tmux CLI
                Analysis       (Claude)    (Codex/Gemini)
```

1. **Discover** — Discord webhooks for real-time issue notifications + 10-minute `gh` poll as safety net.
2. **Plan** — UltraPlan builds the master execution strategy: complexity classification, dependency graph, tool assignment.
3. **Dispatch** — Route to the best agent based on complexity and quota. Claude agents get autoresearch for iterative development.
4. **Verify** — Dedicated Sonnet reviewer checks acceptance criteria + tests.
5. **Simplify** — Sonnet agent runs code simplification pass.
6. **Merge** — PR creation with auto-merge. Sonnet monitor watches CI and review comments.
7. **Cleanup** — Worktrees removed, state updated, issues closed.

## Installation

Add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "extraKnownMarketplaces": {
    "beacon": {
      "source": {
        "source": "github",
        "repo": "Maleick/beacon"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "beacon@beacon": true
  }
}
```

## Prerequisites

- [Claude Code](https://claude.ai/code) with Claude Max subscription
- [GitHub CLI](https://cli.github.com/) (`gh`) — authenticated
- [tmux](https://github.com/tmux/tmux) — v3.0+
- Optional: [Codex CLI](https://github.com/openai/codex) and/or [Gemini CLI](https://github.com/google/gemini-cli)

## Usage

```bash
# Start a tmux session in your repo
tmux new-session -s beacon -c ~/your-repo

# Launch Claude Code
claude

# Start Beacon
/beacon start

# Check status
/beacon status

# Plan without executing
/beacon plan

# Stop gracefully
/beacon stop
```

## Agent Routing

| Complexity | Primary Agent | Fallback             | Strategy          |
| ---------- | ------------- | -------------------- | ----------------- |
| Simple     | Claude Haiku  | Gemini → Codex Spark | Single pass       |
| Medium     | Claude Sonnet | Codex GPT → Gemini   | Iterative         |
| Complex    | Claude Sonnet | Codex GPT → Re-slice | Autoresearch loop |

Claude is the backbone (Max subscription). Codex and Gemini are tactical options with $20 subscription quota tracking.

## Features

- **Quota-aware routing** — Checks tool quota before dispatch, falls through to next option
- **Dependency resolution** — Respects `blocks:` and `depends-on:` markers in issues
- **Autoresearch integration** — Claude agents use modify → verify → keep/discard loops
- **Post-completion pipeline** — verify → simplify → verify → PR → monitor → cleanup
- **Discord integration** — Real-time issue notifications + command channel
- **Tmux grid layout** — All agents visible in tiled panes
- **State persistence** — `.beacon/state.json` + GitHub labels for crash recovery
- **Codex dual-model tracking** — Separate quota tracking for Spark and GPT

## Architecture

```
beacon/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace index
├── commands/
│   └── beacon.md                # /beacon slash command
├── skills/
│   ├── beacon/SKILL.md          # Core orchestration protocol
│   ├── beacon-dispatch/SKILL.md # Agent dispatch logic
│   ├── beacon-verify/SKILL.md   # Verification pipeline
│   └── beacon-status/SKILL.md   # Status display
├── agents/
│   ├── reviewer.md              # Sonnet verification agent
│   └── monitor.md               # CI/PR monitor agent
├── README.md
├── LICENSE
└── BEACON_SPEC.md               # Full specification
```

## Design Principles

- **Opus never writes code** — orchestration decisions only
- **Single repo per session** — clean isolation, no cross-repo state
- **Dynamic concurrency** — scales agents to workload (soft cap 20, hard cap 50)
- **Trust the CI** — auto-merge on green for simple issues
- **Eat your own dog food** — Beacon develops itself through its own issue pipeline

## License

MIT
