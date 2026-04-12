---
name: beacon-dispatch
description: Agent dispatch protocol — worktree creation, prompt generation, tmux pane management, and quota-aware routing
tools: ["Bash", "Agent", "Write", "Read", "TeamCreate"]
---

# Beacon Dispatch Protocol

## Dispatching a Claude Agent (Sonnet/Haiku)

1. Create the worktree:

   ```bash
   git worktree add .beacon/workspaces/<issue-key> -b beacon/<issue-key> main
   ```

2. Write the prompt context to the worktree. Use this exact prompt template:

   ````markdown
   You are a Beacon worker agent. Your job is to implement the following GitHub issue.

   ## Issue: #<number> — <title>

   <full issue body>

   ## Acceptance Criteria

   <parsed from issue body, or generated from issue description>

   ## Instructions

   - You are working in worktree: `.beacon/workspaces/<issue-key>`
   - Your branch is: `beacon/<issue-key>`
   - Base branch is: `main`
   - Run tests after making changes: `<test-command>`
   - Use `/autoresearch:fix` for iterative development (fix → verify → keep/discard → repeat)
   - When finished, write `BEACON_RESULT.md` in the worktree root with your summary (see template below)
   - Do NOT merge, push to main, or close the issue
   - Do NOT modify files outside the scope of this issue
   - Commit your work to the `beacon/<issue-key>` branch

   ## BEACON_RESULT.md Template

   Write this file when you are done:

   ```markdown
   # Result: #<number> — <title>

   ## Status: DONE | PARTIAL | STUCK

   ## Changes Made

   - <file>: <what changed and why>

   ## Tests

   - Test command: `<command>`
   - Result: PASS | FAIL
   - New tests added: yes/no

   ## Notes

   <anything the reviewer should know>
   ```
   ````

3. Use TeamCreate to spawn the teammate in the worktree directory:

   ```
   TeamCreate({
     name: "beacon-<issue-key>",
     teammateMode: "auto"
   })
   ```

   Then spawn the agent with the `team_name` parameter:

   ```
   Agent({
     prompt: "<the prompt from step 2>",
     team_name: "beacon-<issue-key>",
     subagent_type: "general-purpose",
     mode: "auto"
   })
   ```

4. Update `.beacon/state.json` with the dispatch record.

## Dispatching a Codex/Gemini Agent

1. Create the worktree (same as above).

2. Write `BEACON_PROMPT.md` to the worktree with this template:

   ```markdown
   Implement the following GitHub issue in this repository.

   ## Issue: #<number> — <title>

   <full issue body>

   ## Acceptance Criteria

   <parsed from issue body, or generated from issue description>

   ## Instructions

   - Run tests after changes: `<test-command>`
   - Write a file called BEACON_RESULT.md in the repo root when done, containing:
     - Status: DONE, PARTIAL, or STUCK
     - List of files changed and why
     - Test results (command run, pass/fail)
     - Any notes for the reviewer
   - Do NOT push, merge, or close the issue
   - Commit your changes to the current branch
   ```

3. Spawn tmux pane:

   ```bash
   tmux split-window -t beacon -c .beacon/workspaces/<issue-key>
   tmux select-layout -t beacon tiled
   tmux select-pane -t {last} -T "<TOOL>: <issue-key>"
   ```

4. Send the command:

   ```bash
   # For Codex
   tmux send-keys -t {last} "codex -p \"$(cat BEACON_PROMPT.md)\" --auto-edit" Enter

   # For Gemini
   tmux send-keys -t {last} "gemini -p \"$(cat BEACON_PROMPT.md)\"" Enter
   ```

5. Update state file.

## Worktree Failure Handling

If `git worktree add` fails:

1. **Branch already exists**: The issue was previously attempted. Remove stale worktree first:

   ```bash
   git worktree remove .beacon/workspaces/<issue-key> --force 2>/dev/null
   git branch -D beacon/<issue-key> 2>/dev/null
   git worktree add .beacon/workspaces/<issue-key> -b beacon/<issue-key> main
   ```

2. **Disk space**: Log error, mark issue as `blocked` in state, skip to next issue.

3. **Lock file conflict**: Another process holds the worktree lock.
   ```bash
   # Check for stale lock
   rm -f .git/worktrees/<issue-key>/locked 2>/dev/null
   # Retry once
   git worktree add .beacon/workspaces/<issue-key> -b beacon/<issue-key> main
   ```

If worktree creation fails after retry, skip this issue and continue with the next.

## Quota Check

Before dispatching to any non-Claude tool, check the full fallback chain:

```bash
# Check Codex quota (two separate pools)
codex status 2>&1  # Parse "Spark: X% remaining" and "GPT: X% remaining"

# Check Gemini quota
gemini status 2>&1  # Parse remaining quota percentage
```

**Fallback chain by complexity:**

| Complexity | Try 1                        | Try 2 (if Try 1 < 10%) | Try 3 (if Try 2 < 10%)   | Last resort                       |
| ---------- | ---------------------------- | ---------------------- | ------------------------ | --------------------------------- |
| Simple     | Claude Haiku                 | Gemini                 | Codex Spark              | Claude Haiku (accept rate limit)  |
| Medium     | Claude Sonnet                | Codex GPT              | Gemini                   | Claude Sonnet (accept rate limit) |
| Complex    | Claude Sonnet + autoresearch | Codex GPT              | Re-slice into sub-issues | Claude Sonnet (accept rate limit) |

Claude is always the last resort — Max subscription has generous limits. If even Claude is rate-limited, pause dispatch and wait for quota recovery.

Update `.beacon/state.json` tool quota after each check.

## Completion Detection

For tmux-based agents (Codex/Gemini):

```bash
# Check if pane process has exited
tmux list-panes -t beacon -F '#{pane_id} #{pane_dead} #{pane_title}'
# pane_dead = 1 means agent CLI exited
```

For Claude agents: TeamCreate protocol handles completion signaling natively.
