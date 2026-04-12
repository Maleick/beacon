# Beacon

Autonomous multi-agent orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Routes GitHub issues to AI CLI tools (Claude, Codex, Gemini, Grok), verifies results, and auto-merges approved work.

## Architecture

Beacon v3 uses an **Advisor + Monitor** pattern: Sonnet runs the event loop, Opus advises at strategic decision points, and Haiku handles lightweight triage.

### Four-Tier Model

```mermaid
graph TB
    subgraph "Tier 1: Bash"
        M1[Agent Monitor<br/>5s poll]
        M2[PR Monitor<br/>30s poll]
        M3[Issue Monitor<br/>60s poll]
    end

    subgraph "Tier 2: Haiku"
        ET[Event Triage]
        EQ[Event Queue<br/>.beacon/event-queue.json]
        SW[Simple Worker]
        NF[Nit Fixer]
    end

    subgraph "Tier 3: Sonnet"
        ORC[Orchestrator]
        MW[Medium/Complex Worker]
        REV[Reviewer]
        PR[PR Creator]
    end

    subgraph "Tier 4: Opus"
        UP[UltraPlan]
        ADV[Advisor]
    end

    M1 --> ET
    M2 --> ET
    M3 --> ET
    ET --> EQ
    EQ --> ORC
    ORC --> SW
    ORC --> MW
    ORC --> REV
    REV --> PR
    ORC -.->|escalation| ADV
    ADV -.->|decisions| ORC
    UP -.->|initial plan| ORC
    NF --> PR

    style M1 fill:#e3f2fd
    style M2 fill:#e3f2fd
    style M3 fill:#e3f2fd
    style ET fill:#fff3e0
    style EQ fill:#fff3e0
    style SW fill:#fff3e0
    style NF fill:#fff3e0
    style ORC fill:#e8f5e9
    style MW fill:#e8f5e9
    style REV fill:#e8f5e9
    style PR fill:#e8f5e9
    style UP fill:#fce4ec
    style ADV fill:#fce4ec
```

### Event Flow

```mermaid
sequenceDiagram
    participant B as Bash Monitor
    participant H as Haiku Triage
    participant Q as Event Queue
    participant S as Sonnet Orchestrator
    participant R as Reviewer
    participant O as Opus Advisor
    participant GH as GitHub

    Note over B,GH: Agent completes work
    B->>H: [AGENT_STATUS] key=issue-25 status=COMPLETE
    H->>Q: {type: "verify", issue: "issue-25"}
    S->>Q: Pull next event
    Q->>S: verify issue-25
    S->>R: Spawn reviewer agent
    R->>S: VERDICT: PASS
    S->>GH: Create PR

    Note over B,GH: Agent gets stuck (2nd attempt)
    B->>H: [AGENT_STATUS] key=issue-30 status=STUCK
    H->>Q: {type: "stuck", issue: "issue-30", attempt: 2}
    S->>Q: Pull next event
    S->>O: "Issue #30 failed twice. Re-slice or block?"
    O->>S: "Re-slice into #30a and #30b"
    S->>GH: Create sub-issues
```

### Dispatch Strategy

```mermaid
flowchart LR
    I[GitHub Issue] --> C{Complexity?}
    C -->|Simple| TP1{Third-party<br/>available?}
    C -->|Medium| TP2{Third-party<br/>available?}
    C -->|Complex| SN2[Sonnet Worker<br/>+ autoresearch]

    TP1 -->|Yes| CX1[Codex/Gemini/Grok]
    TP1 -->|No| HK[Haiku Worker]
    TP2 -->|Yes| CX2[Codex/Gemini/Grok]
    TP2 -->|No| SN1[Sonnet Worker]

    CX1 --> V[Verify Pipeline]
    CX2 --> V
    HK --> V
    SN1 --> V
    SN2 --> V

    V -->|PASS| PR[Create PR]
    V -->|FAIL attempt 1| RE[Retry with context]
    V -->|FAIL attempt 2+| OP[Opus Advisor]
    RE --> V
    OP -->|re-slice| I
    OP -->|block| BL[Blocked]

    style CX1 fill:#e3f2fd
    style CX2 fill:#e3f2fd
    style HK fill:#fff3e0
    style SN1 fill:#e8f5e9
    style SN2 fill:#e8f5e9
    style OP fill:#fce4ec
```

### CI Autofix Loop

```mermaid
flowchart TD
    CI[CI Failure Detected] --> CL{Error Type?}
    CL -->|Lint/Format/Type| HK[Haiku fixes]
    CL -->|Test/Build| SN[Sonnet fixes]
    HK --> P[Push + Re-trigger CI]
    SN --> P
    P --> R{CI Result?}
    R -->|Pass| D[Done]
    R -->|Fail again| CT{Attempt count?}
    CT -->|< 2| CL
    CT -->|>= 2| OP[Opus Advisor]
    OP -->|re-approach| CL
    OP -->|block| BL[Block PR]

    style HK fill:#fff3e0
    style SN fill:#e8f5e9
    style OP fill:#fce4ec
```

## Plugin Structure

```
beacon/
  .claude-plugin/plugin.json    # Plugin metadata
  skills/
    beacon/SKILL.md             # Core orchestration skill
    beacon-dispatch/SKILL.md    # Agent dispatch protocol
    beacon-verify/SKILL.md      # Verification pipeline
    beacon-status/SKILL.md      # Status display
    beacon-poll/SKILL.md        # GitHub issue sync
  commands/
    beacon.md                   # /beacon start|status|stop|plan|help
  agents/
    reviewer.md                 # Structured verification agent
    monitor.md                  # PR/CI monitoring agent
  hooks/
    beacon-init.sh              # Initialize .beacon/ workspace
    detect-tools.sh             # Detect available AI CLIs + quota
    update-state.sh             # State machine transitions + GitHub labels
    check-completion.sh         # Query tmux for dead panes
    cleanup-worktree.sh         # Remove worktree, branch, close issue
    sweep-stale.sh              # Clean up orphaned worktrees
```

## State Management

- **Local**: `.beacon/state.json` — issues, plan phases, tool quotas, stats
- **Durable**: GitHub labels (`beacon:in-progress`, `beacon:blocked`, `beacon:paused`, `beacon:done`) for cross-session recovery
- **Event queue**: `.beacon/event-queue.json` — Haiku writes, Sonnet reads

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `gh` (GitHub CLI, authenticated)
- `tmux` (for third-party agent dispatch)
- `jq` (JSON processing)
- Git repository with GitHub remote

## Usage

```bash
# Start autonomous orchestration
/beacon start

# Check status of all agents and issues
/beacon status

# View the current plan
/beacon plan

# Stop all agents gracefully
/beacon stop
```

## License

MIT
