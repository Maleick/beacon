---
name: autoship-setup
description: Interactive setup wizard for AutoShip on OpenCode — model selection, tool detection, concurrency tuning
platform: opencode
tools: ["Bash", "question", "Write"]
---

# AutoShip Setup Wizard — OpenCode Port

Guide users through model selection and configuration on first run.

---

## Flow Overview

1. **Model Selection** — Which tools?
2. **Tool Detection** — Check for Codex CLI and Gemini
3. **Concurrency** — How many agents?
4. **Summary** — Ready to go

---

## Step 1: Model Configuration

Ask the user:

```
Which model configuration?

◉ Lean (Claude only)
  └ Haiku for simple, Sonnet for complex
  └ No external dependencies
  └ Single quota pool
  └ Recommended if: limited Claude quota, prefer simplicity

◯ Balanced (Claude + Codex)
  └ Codex CLI for simple/medium
  └ Claude for complex/risky issues
  └ Requires: Codex CLI installed

◯ Maxed (All tools)
  └ Claude + Codex CLI + Gemini CLI
  └ Maximum parallelism
  └ Requires: Codex CLI + Gemini CLI
```

---

## Step 2: Tool Detection

**For Balanced/Maxed:**

```bash
command -v codex >/dev/null 2>&1 && echo "✓ Codex CLI available" || echo "⚠ Codex CLI not found"
```

**For Maxed:**

```bash
command -v gemini >/dev/null 2>&1 && echo "✓ Gemini CLI available" || echo "⚠ Gemini CLI not found"
```

---

## Step 3: Concurrency

Ask:

```
How many concurrent agents?

◉ Conservative (5 agents)
  └ Lowest cost, good for testing

◯ Standard (10 agents)
  └ Balanced throughput/cost

◯ Aggressive (20 agents)
  └ Maximum parallelism
```

---

## Step 4: Generate Config

```bash
# Create .autoship directory
mkdir -p .autoship

# Write config
jq -n \
  --arg config "$CONFIG" \
  --arg max_agents "$MAX_AGENTS" \
  '{
    model_config: $config,
    max_agents: ($max_agents | tonumber),
    onboarded_at: (now | todate)
  }' > .autoship/config.json

# Mark as onboarded
date -u +%Y-%m-%dT%H:%M:%SZ > .autoship/.onboarded
```

---

## Step 5: Summary

```
✓ AutoShip configured!

Model configuration: <config>
Available tools: Claude<, Codex, Gemini>
Concurrency: <N> agents

Next: Run /autoship to start
```

---

## Error Recovery

| Error | Recovery |
|-------|----------|
| Codex not found | Fallback to Lean |
| Gemini not found | Optional, proceed without |
| Config write fails | Check file permissions |

---

## Reconfiguration

```bash
rm .autoship/.onboarded
# Then re-run /autoship-setup
```
