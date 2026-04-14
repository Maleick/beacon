---
name: setup
description: Interactive setup wizard for model selection, API key configuration, and agent concurrency tuning
tools: ["Bash", "AskUserQuestion", "Write"]
---

# AutoShip Setup Wizard — User Model Configuration

You are the setup wizard. Your goal: guide users through model selection, secret management, and concurrency tuning on their first run.

---

## Flow Overview

1. **Model Selection** — Which tools? (Lean/Balanced/Maxed)
2. **Secret Management** — OpenAI API key?
3. **Concurrency** — How many agents?
4. **Verification** — Detect tools + write config
5. **Summary** — Ready to go

---

## Step 1: Model Configuration

Ask the user which model setup fits their needs:

```
Which model configuration?

◉ Lean (Claude only)
  └ Haiku for simple, Opus for complex
  └ No external dependencies
  └ Single quota pool
  └ Recommended if: limited Claude quota, prefer simplicity

◯ Balanced (Claude + Codex)
  └ Codex for simple/medium (cheaper, faster)
  └ Claude for complex/risky issues
  └ Requires: OpenAI API key
  └ Recommended if: you have OpenAI subscription

◯ Maxed (All tools)
  └ Claude + Codex + Gemini
  └ Maximum parallelism for CI/batch
  └ Requires: OpenAI API key + Gemini API key
  └ Recommended if: throughput is critical
```

Store choice as `AUTOSHIP_MODEL_CONFIG` in `~/.claude/settings.json` env section.

---

## Step 2: API Key Setup

**If user chose `balanced` or `maxed`:**

Ask: "Do you have an OpenAI API key?"

**If YES:**

1. Prompt for paste (no echo): "Paste your API key (will not echo):"
2. Store to `~/.claude/.secrets/openai` with 0600 perms:
   ```bash
   mkdir -p ~/.claude/.secrets
   echo "$API_KEY" > ~/.claude/.secrets/openai
   chmod 600 ~/.claude/.secrets/openai
   ```
3. Verify with Codex detection:
   ```bash
   timeout 5s bash hooks/detect-tools.sh 2>/dev/null | jq '.["codex-spark"].available' || echo false
   ```

   - If true: "✓ Codex verified. Quota estimate: ${quota}%"
   - If false: "⚠ Codex unavailable. Check API key, or ensure Codex CLI installed (`codex --version`). Falling back to Claude only."

**If NO:**

- Warn: "Codex unavailable without OpenAI API key. Falling back to Lean (Claude only)."
- Set `AUTOSHIP_MODEL_CONFIG` to `lean`

**If user chose `maxed` and Codex works:**

Ask: "Do you have a Gemini API key?"

**If YES:**

1. Store to `~/.claude/.secrets/gemini` with 0600 perms
2. Verify: `timeout 5s bash hooks/detect-tools.sh 2>/dev/null | jq '.["gemini"].available' || echo false`
   - If true: "✓ Gemini verified."
   - If false: "⚠ Gemini unavailable. Ensure Gemini CLI installed. Proceeding with Claude + Codex."

**If NO:**

- Info: "Gemini optional. Proceeding with Claude + Codex."

---

## Step 3: Concurrency Preference

Ask: "How many concurrent agents?"

```
◉ Conservative (5 agents)
  └ Lowest cost
  └ Good for testing/prototyping
  └ Safe on shared machines

◯ Standard (10 agents)
  └ Balanced throughput/cost
  └ Default recommendation
  └ Fits most workflows

◯ Aggressive (20 agents)
  └ Maximum parallelism (hard cap)
  └ Best for CI/high-volume batch
  └ Costs scale linearly
```

Store choice as `AUTOSHIP_MAX_AGENTS` in env section: `"5|10|20"`.

---

## Step 4: Verification & Config Generation

Run post-setup automation:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Detect available tools + quota
TOOLS=$(bash hooks/detect-tools.sh 2>/dev/null || echo '{}')
echo "Detecting tools..."
echo "$TOOLS" | jq -r 'to_entries[] | "\(.key): \(.value.available) (quota: \(.value.quota_pct)%)"'

# 2. Create .autoship directory
mkdir -p .autoship

# 3. Update ~/.claude/settings.json with choices
jq ".env.AUTOSHIP_MODEL_CONFIG = \"$CONFIG\"" ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
jq ".env.AUTOSHIP_MAX_AGENTS = \"$MAX_AGENTS\"" ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json

# 4. Mark as onboarded
date -u +%Y-%m-%dT%H:%M:%SZ > .autoship/.onboarded

echo "✓ Setup complete!"
```

---

## Step 5: Summary

Output a summary:

```
✓ AutoShip configured!

Model configuration: ${CONFIG} (${TOOLS_AVAILABLE})
Concurrency: ${MAX_AGENTS} agents
API keys stored: ~/.claude/.secrets/{openai,gemini}

Next: /autoship:start
```

---

## Error Recovery

| Error                       | Recovery                                                     |
| --------------------------- | ------------------------------------------------------------ |
| Invalid OpenAI key          | Re-run setup; skip Codex; fallback to Lean                   |
| Missing jq                  | Abort with install instructions: `brew install jq`           |
| Offline (quota check fails) | Assume 100% quota available; user can manually refresh later |
| Settings.json not writable  | Abort; user must check file perms                            |

---

## Reconfiguration

User can reset onboarding at any time:

```bash
rm .autoship/.onboarded
/autoship:setup
```

Or manually update settings:

```bash
jq '.env.AUTOSHIP_MODEL_CONFIG = "maxed"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
/autoship:start
```

---

## Integration with SessionStart

`hooks/activate.sh` checks on every session:

```bash
if [[ ! -f .autoship/.onboarded ]]; then
  echo "First run detected. Launching setup wizard..."
  bash hooks/setup.sh  # Runs setup logic
  # Or via Skill tool:
  # Skill("setup")
fi
```

If onboarding flag exists, skip setup and proceed to orchestration.
