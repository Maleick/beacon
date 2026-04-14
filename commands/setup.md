---
name: setup
description: Interactive setup wizard for first-time configuration and model selection
tools: ["Bash", "AskUserQuestion", "Write"]
---

# AutoShip Setup Wizard

First-run configuration for model selection, API key management, and concurrency tuning.

## Startup Detection

On every SessionStart, `hooks/activate.sh` checks:

```bash
[[ -f .autoship/.onboarded ]] || bash hooks/setup.sh
```

If `.onboarded` is missing, the setup script prompts the user interactively.

---

## Interactive Flow

You are the setup wizard. Guide the user through three questions.

### Step 1: Model Configuration

Present three options with descriptions:

**Lean (Claude only)**

- Haiku for simple issues, Opus for complex
- No external dependencies
- Single quota pool
- Recommended if: limited Claude quota, or prefer simplicity

**Balanced (Claude + Codex)**

- Codex for simple/medium (cheaper, faster)
- Claude for complex/risky
- Requires OpenAI API key (read usage via API)
- Recommended if: you have OpenAI subscription

**Maxed (All tools)**

- Adds Gemini for additional parallelism
- Claude + Codex + Gemini dispatch
- Requires OpenAI API key + Gemini API key
- Recommended if: maximum throughput needed (CI/batch work)

**User choice:** Store in `~/.claude/settings.json` env section:

```json
"AUTOSHIP_MODEL_CONFIG": "lean|balanced|maxed"
```

---

### Step 2: API Key Setup

If user chose `balanced` or `maxed`:

"Do you have an OpenAI API key?"

**If YES:**

- Prompt: "Paste your API key (will not echo):"
- Store in `~/.claude/.secrets/openai` with 0600 perms:
  ```bash
  mkdir -p ~/.claude/.secrets
  echo "$API_KEY" > ~/.claude/.secrets/openai
  chmod 600 ~/.claude/.secrets/openai
  ```
- Verify with `timeout 5s bash hooks/detect-tools.sh | jq '.["codex-spark"]'`
  - If available: "✓ Codex detected. Quota: ${quota}%"
  - If unavailable: "⚠ Codex not available. Check API key or Codex CLI."

**If NO:**

- Warn: "Codex unavailable without API key. Falling back to Claude only."
- Set `AUTOSHIP_MODEL_CONFIG` to `lean`

---

### Step 3: Concurrency Preference

"How many concurrent agents?"

**Conservative (5 agents)**

- Lowest cost
- Good for testing/prototyping
- Safe on shared machines

**Standard (10 agents)**

- Balanced throughput/cost
- Default recommendation
- Fits most workflows

**Aggressive (20 agents)**

- Maximum parallelism
- Full hard cap
- Best for CI/high-volume batch

**User choice:** Store in `~/.claude/settings.json` env section:

```json
"AUTOSHIP_MAX_AGENTS": "5|10|20"
```

---

## Post-Setup Actions

1. Create onboarding flag:

```bash
mkdir -p .autoship
touch .autoship/.onboarded
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .autoship/.onboarded
```

2. Update `.autoship/state.json` tools section with detected quota:

```bash
bash hooks/detect-tools.sh | jq . > /tmp/tools.json
# Merge into state.json
```

3. Generate/update `.autoship/routing.json` based on config choice:

```bash
# See hooks/init.sh for routing generation logic
# Routes are dynamically built per AUTOSHIP_MODEL_CONFIG
```

4. Summary output:

```
✓ Setup complete!

Configuration: ${CONFIG_NAME}
Concurrency: ${MAX_AGENTS} agents
API keys: ${KEYS_CONFIGURED}

Run: /autoship:start
```

---

## Reconfiguration

User can reset:

```bash
rm .autoship/.onboarded
/autoship:setup
```

Or manually edit:

```bash
jq '.env.AUTOSHIP_MODEL_CONFIG = "balanced"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

---

## Error Handling

- **Invalid OpenAI key**: `detect-tools.sh` fails gracefully; falls back to Claude only
- **Missing jq**: Abort with instructions to install via `brew install jq`
- **Offline quota check**: Assume 100% quota available (safe default; avoids false negatives)
