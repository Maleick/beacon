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

2. Write the prompt context to the worktree:
   - Issue title, description, acceptance criteria
   - Instruction to use `/autoresearch:fix` for iterative development (Sonnet/complex only)
   - Instruction to write `BEACON_RESULT.md` on completion
   - Instruction to NOT merge, push, or close the issue

3. Use TeamCreate to spawn the teammate in the worktree directory.

4. Update `.beacon/state.json` with the dispatch record.

## Dispatching a Codex/Gemini Agent

1. Create the worktree (same as above).

2. Write `BEACON_PROMPT.md` to the worktree with:
   - Full issue context
   - Acceptance criteria
   - Instruction to write `BEACON_RESULT.md` on completion
   - The repo's test command for self-verification

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

## Quota Check

Before dispatching to any non-Claude tool:

```bash
codex status 2>&1  # Parse quota from output
gemini status 2>&1  # Parse quota from output
```

If quota < 10%, skip tool. If all non-Claude tools exhausted, route through Claude.

## Completion Detection

For tmux-based agents (Codex/Gemini):

```bash
# Check if pane process has exited
tmux list-panes -t beacon -F '#{pane_id} #{pane_dead} #{pane_title}'
# pane_dead = 1 means agent CLI exited
```

For Claude agents: TeamCreate protocol handles completion signaling natively.
