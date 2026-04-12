# Beacon v3 Architecture — Advisor + Monitor Pattern

Status: Draft — Design Discussion
Updated: 2026-04-12

---

## 1. Design Philosophy

Beacon v3 inverts the orchestration model. Instead of Opus running a constant loop and spawning workers, **Sonnet is the executor** — it reacts to events, handles dispatch, and runs the pipeline. **Opus is the advisor** — called only at strategic decision points where higher intelligence changes the outcome.

This mirrors Anthropic's Advisor tool pattern (API beta `advisor-tool-2026-03-01`), adapted for the Claude Code plugin runtime using native Agent spawning and the Monitor tool.

### Core Principles

1. **Event-driven, not poll-driven** — Monitor tools stream events into the conversation. No CronCreate polling loops.
2. **Sonnet-first execution** — The bulk of orchestration runs at Sonnet-level. Mechanical work doesn't need Opus.
3. **Opus for strategy only** — UltraPlan, re-dispatch decisions, ambiguous verdicts, phase checkpoints.
4. **Fresh context per advisor call** — Opus gets spawned with focused context, not accumulated noise.

---

## 2. Model Roles

| Model      | Role                    | When Active                                                                                |
| ---------- | ----------------------- | ------------------------------------------------------------------------------------------ |
| **Opus**   | Advisor                 | Spawned at decision points: UltraPlan, re-dispatch, checkpoints, LOW_CONFIDENCE reviews    |
| **Sonnet** | Executor / Orchestrator | Main loop — reacts to Monitor events, dispatches agents, runs verify pipeline, creates PRs |
| **Sonnet** | Worker (medium/complex) | Dispatched to worktrees for medium and complex issues                                      |
| **Haiku**  | Worker (simple)         | Dispatched to worktrees for simple issues                                                  |
| **Sonnet** | Reviewer                | Verification agent ��� structured I/O, test discovery, verdicts                            |
| **Sonnet** | Monitor agent           | PR/CI monitoring via the beacon-monitor agent definition                                   |

### Advisor Call Points

Opus is spawned (via `Agent` with `model: "opus"`) at these moments:

1. **UltraPlan** — After issues are fetched, Opus classifies complexity, builds dependency graph, assigns tools, plans phases
2. **Re-dispatch decision** — Agent failed verification. Retry same tool? Different tool? Re-slice the issue?
3. **Phase checkpoint** — A dispatch phase completed. Opus reviews results and adjusts the plan for the next phase
4. **LOW_CONFIDENCE verdict** — Sonnet reviewer returned LOW_CONFIDENCE. Opus makes the final call
5. **Stuck detection** — Same issue failed 2+ times. Opus decides: block it, re-approach, or escalate to human

### Advisor Call Format

Each Opus advisor call gets a focused prompt:

```
You are Beacon's strategic advisor. Review the current state and provide a decision.

## Context
<current state summary from .beacon/state.json>
<specific decision needed>

## Options
<enumerated choices with tradeoffs>

## Constraints
<quota status, time pressure, dependency state>

Respond with: your decision, reasoning (1-2 sentences), and any plan adjustments.
Keep response under 200 words.
```

---

## 3. Event Architecture

### Monitor-Based Event Stream

Three persistent Monitor processes run for the session lifetime:

#### Monitor 1: Agent Completion Watcher

```bash
# Watch for tmux pane deaths (agent completion)
while true; do
  tmux list-panes -t beacon -F '#{pane_id} #{pane_dead} #{pane_title}' 2>/dev/null | \
    while IFS=' ' read -r id dead title; do
      if [[ "$dead" == "1" ]]; then
        echo "[AGENT_DONE] pane=$id title=$title"
      fi
    done
  sleep 5
done
```

Sonnet reacts: read BEACON_RESULT.md → run verify pipeline → create PR or re-dispatch.

#### Monitor 2: GitHub Issue Watcher

```bash
# Poll GitHub for new/changed/closed issues
last_check=$(date -u +%Y-%m-%dT%H:%M:%SZ)
while true; do
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # New issues since last check
  new=$(gh api "repos/OWNER/REPO/issues?state=open&since=$last_check&sort=created" --jq '.[].number' 2>/dev/null)
  for num in $new; do
    echo "[ISSUE_NEW] number=$num"
  done
  # Closed issues
  closed=$(gh api "repos/OWNER/REPO/issues?state=closed&since=$last_check&sort=updated" --jq '.[].number' 2>/dev/null)
  for num in $closed; do
    echo "[ISSUE_CLOSED] number=$num"
  done
  last_check=$now
  sleep 60
done
```

Sonnet reacts: new issues → call Opus advisor for classification → add to plan. Closed issues → cancel running agent.

#### Monitor 3: PR Status Watcher

```bash
# Watch Beacon PRs for CI completion, review comments, merges
while true; do
  gh pr list --label beacon --state open --json number,mergeable,statusCheckRollup 2>/dev/null | \
    jq -r '.[] | "\(.number) \(.mergeable) \(.statusCheckRollup // [] | map(.conclusion) | join(","))"' | \
    while read -r num mergeable checks; do
      if echo "$checks" | grep -q "SUCCESS"; then
        echo "[PR_CI_PASS] number=$num"
      elif echo "$checks" | grep -q "FAILURE"; then
        echo "[PR_CI_FAIL] number=$num"
      fi
      if [[ "$mergeable" == "CONFLICTING" ]]; then
        echo "[PR_CONFLICT] number=$num"
      fi
    done
  # Check for recently merged
  gh pr list --label beacon --state merged --json number,mergedAt 2>/dev/null | \
    jq -r '.[] | "[PR_MERGED] number=\(.number)"'
  sleep 30
done
```

Sonnet reacts: CI pass → merge (simple) or review first (medium/complex). CI fail → report. Conflict → call Opus advisor. Merged → cleanup worktree.

### Event Processing Model

Events arrive as Monitor notifications in the conversation. Sonnet processes them sequentially:

```
1. Monitor fires: [AGENT_DONE] pane=%3 title=HAIKU: issue-25
2. Sonnet reads BEACON_RESULT.md from worktree
3. Sonnet spawns reviewer agent (Sonnet model)
4. Reviewer returns PASS
5. Sonnet creates PR
6. Meanwhile, if more events queued, process next after current pipeline completes
```

For events that need strategic decisions, Sonnet spawns Opus:

```
1. Monitor fires: [AGENT_DONE] — reviewer returns FAIL (2nd attempt)
2. Sonnet spawns Opus advisor: "Issue #25 failed verification twice. Codex and Haiku both failed. Should we try Sonnet, re-slice, or block?"
3. Opus returns: "Re-slice. The issue scope is too broad for a single agent. Split into #25a (validation) and #25b (error handling)."
4. Sonnet creates the sub-issues and dispatches
```

---

## 4. Startup Sequence (Revised)

```
1. Sonnet validates environment (gh, tmux, git repo)
2. Sonnet detects available tools + checks quota (hooks/detect-tools.sh)
3. Sonnet loads .beacon/state.json or runs hooks/beacon-init.sh
4. Sonnet fetches open issues via gh
5. → ADVISOR CALL: Opus runs UltraPlan
   - Classifies complexity per issue
   - Builds dependency graph
   - Assigns tools based on complexity + quota
   - Plans dispatch phases
   - Returns: structured plan JSON
6. Sonnet stores plan in .beacon/state.json
7. Sonnet starts 3 persistent Monitors (agent, issue, PR watchers)
8. Sonnet dispatches Phase 1 agents
9. Sonnet enters reactive mode — waits for Monitor events
```

---

## 5. Dispatch Protocol (Revised)

Sonnet handles all dispatch directly:

### Simple Issues → Haiku Worker

```
Agent({
  model: "haiku",
  prompt: "<beacon worker prompt>",
  mode: "auto"
})
```

### Medium Issues → Sonnet Worker

```
Agent({
  model: "sonnet",
  prompt: "<beacon worker prompt with autoresearch>",
  mode: "auto"
})
```

### Complex Issues → Sonnet Worker + Opus Advisor

```
Agent({
  model: "sonnet",
  prompt: "<beacon worker prompt with autoresearch + note: this is complex>",
  mode: "auto"
})
// After completion, Opus reviews the work before proceeding to PR
```

### Codex/Gemini → tmux CLI (unchanged)

Same tmux dispatch protocol as v2.

---

## 6. Comparison: v2 vs v3

| Aspect              | v2 (Current)                  | v3 (Advisor + Monitor)                    |
| ------------------- | ----------------------------- | ----------------------------------------- |
| Orchestrator        | Opus (always on)              | Sonnet (event-driven)                     |
| Strategic decisions | Opus makes every decision     | Opus called 3-5 times per session         |
| Event detection     | CronCreate poll (10 min)      | Monitor (5-60 sec, event-driven)          |
| Worker dispatch     | Opus → Sonnet/Haiku           | Sonnet → Haiku/Sonnet                     |
| Context usage       | Opus accumulates full session | Opus gets fresh, focused context          |
| Reviewer            | Sonnet (same)                 | Sonnet (same)                             |
| Cost model (API)    | Opus rates for everything     | Sonnet rates + Opus for ~5 calls          |
| Cost model (Max)    | Flat rate                     | Flat rate (but better context efficiency) |

---

## 7. Open Design Questions

- [ ] Should Monitors be consolidated into one unified watcher?
- [ ] Haiku tier: simple worker only, or also run lightweight monitors?
- [ ] Opus advisor call budget: hard cap per session? Per phase?
- [ ] Should the main executor skill be a rewrite or a wrapper around v2?
- [ ] How to handle Monitor event storms (e.g., 5 agents complete simultaneously)?
