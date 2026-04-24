---
name: autoship-dispatch
description: Agent dispatch for OpenCode — creates worktrees, generates prompts, and dispatches via Agent subagents with quota-aware routing
platform: opencode
tools: ["Bash", "Agent", "Write", "Read"]
---

# AutoShip Dispatch Protocol — OpenCode Port

Third-party tools (Codex/Gemini) are dispatched first for simple and medium issues. Claude agents are reserved for complex work and fallback.

---

## Dispatch Priority Matrix

| Complexity | Primary | Fallback | Last Resort |
| ---------- | ------- | -------- | ----------- |
| Simple | Codex/Gemini (quota > 10%) | Claude Haiku | Claude Sonnet |
| Medium | Codex/Gemini (quota > 10%) | Claude Sonnet | Claude Sonnet |
| Complex | Claude Sonnet | Claude Sonnet retry | Opus advisor |

---

## Step 1: Create Worktree

```bash
ISSUE_KEY="issue-<number>"
git worktree add .autoship/workspaces/$ISSUE_KEY -b autoship/$ISSUE_KEY main
```

If branch already exists:
```bash
git worktree remove .autoship/workspaces/$ISSUE_KEY --force 2>/dev/null
git branch -D autoship/$ISSUE_KEY 2>/dev/null
git worktree add .autoship/workspaces/$ISSUE_KEY -b autoship/$ISSUE_KEY main
```

---

## Step 2: Check Quota

```bash
# Read quota from .autoship/quota.json
quota_codex=$(jq -r '.["codex-spark"].quota_pct // 100' .autoship/quota.json)
quota_gemini=$(jq -r '.gemini.quota_pct // 100' .autoship/quota.json)
```

Skip tools with quota_pct <= 10 (warning zone) or quota_pct == 0 (exhausted).

---

## Step 3: Dispatch Agent

### Claude Haiku/Sonnet (OpenCode Agent)

```
Agent({
  model: "haiku",  # or "sonnet"
  prompt: "<dispatch prompt>",
  description: "AutoShip: issue-<number>"
})
```

#### Dispatch Prompt Template

```markdown
You are an AutoShip worker agent. Implement the following GitHub issue.

## Issue: #<number> — <title>

## Issue Body
<full issue body>

## Acceptance Criteria
<parsed from issue body>

## Project Context
$(cat .autoship/project-context.md 2>/dev/null || echo "No project context available.")

## Working Context
- Worktree: `.autoship/workspaces/<issue-key>`
- Branch: `autoship/<issue-key>`
- Base: `main`
- Test command: `<test-command>`

## Instructions
- Stay within the scope of this issue
- Run tests after making changes
- Commit your work to `autoship/<issue-key>`
- Do NOT push, merge, or close the issue

## When Finished
Write `AUTOSHIP_RESULT.md` to `.autoship/workspaces/<issue-key>/`

```markdown
# Result: #<number> — <title>

## Status: DONE | PARTIAL | STUCK

## Changes Made
- <file>: <what changed>

## Tests
- Command: `<test-command>`
- Result: PASS | FAIL

## Notes
<anything the reviewer should know>
```

Then write your status to `.autoship/workspaces/<issue-key>/status`:
- `COMPLETE` — if successful
- `BLOCKED` — if external dependency
- `STUCK` — if cannot solve

Print COMPLETE, BLOCKED, or STUCK as your final output.
```

### Third-Party Tools (Codex/Gemini)

```bash
cd .autoship/workspaces/$ISSUE_KEY

# Write prompt file
cat > AUTOSHIP_PROMPT.md << 'EOF'
<dispatch prompt>
EOF

# Dispatch via CLI
codex -p "$(cat AUTOSHIP_PROMPT.md)" &
# or
gemini -p "$(cat AUTOSHIP_PROMPT.md)" --yolo &

# Wait for completion, then check for AUTOSHIP_RESULT.md
```

---

## Step 4: Update State

```bash
# Update state
bash hooks/update-state.sh set-running <issue-id> agent=<agent-name>

# Update quota
bash hooks/quota-update.sh decrement <tool> <complexity>

# Initialize status file
echo "RUNNING" > .autoship/workspaces/<issue-key>/status
```

---

## Agent Completion Requirements

**Before printing COMPLETE/BLOCKED/STUCK, agents MUST:**

1. Commit all work to git:
   ```bash
   git add -A && git commit -m 'feat: <issue-title> (#<number>)'
   ```

2. Write `AUTOSHIP_RESULT.md`:
   ```bash
   cat > .autoship/workspaces/<issue-key>/AUTOSHIP_RESULT.md << 'EOF'
   # Result: #<number> — <title>
   ## Status: DONE | PARTIAL | STUCK
   ## Changes Made
   - <file>: <what changed>
   ## Tests
   - Result: PASS | FAIL
   ## Notes
   <notes>
   EOF
   ```

3. Write status file:
   ```bash
   echo "COMPLETE" > .autoship/workspaces/<issue-key>/status
   ```

---

## Haiku Failure Escalation

If Haiku fails verification:
- **Attempt 1 fail**: Re-dispatch Haiku with failure context
- **Attempt 2 fail**: Automatically escalate to Sonnet
- **Attempt 3+ fail**: Spawn Opus advisor

---

## Opus Advisor (Complex Issues)

For complex issues, spawn Opus first for architectural guidance:

```
Agent({
  model: "opus",
  prompt: "You are the AutoShip Architectural Advisor. Analyze this issue and provide implementation guidance.

## Issue
<issue body>

## Project Context
$(cat .autoship/project-context.md 2>/dev/null || echo "")

## Instructions
Output a JSON object with:
- key_files: most relevant files
- approach: implementation strategy
- risks: potential pitfalls

Keep response under 200 words.",
  description: "Opus advisor: issue-<number>"
})
```

Insert the brief into the Sonnet dispatch prompt.

---

## Concurrency Cap

Before dispatching, check running count:

```bash
RUNNING=$(jq '[.issues | to_entries[] | select(.value.state == "running")] | length' .autoship/state.json)
if (( RUNNING >= 20 )); then
  echo "CAP_REACHED: $RUNNING agents running"
  # Queue for next poll cycle
  exit 0
fi
```
