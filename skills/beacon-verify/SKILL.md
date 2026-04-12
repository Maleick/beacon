---
name: beacon-verify
description: Post-completion verification pipeline — review, simplify, re-verify, PR, monitor, cleanup
tools: ["Bash", "Agent", "Read", "Write"]
---

# Beacon Verification Pipeline

Invoked after an agent reports completion. Runs the full verify → simplify → verify → PR → monitor → cleanup pipeline.

## Step 1: Initial Verification

Spawn the `beacon-reviewer` agent with:

- Issue acceptance criteria
- Contents of `BEACON_RESULT.md` from the worktree
- Output of `git diff main...beacon/<issue-key>` for the code changes
- Output of running the repo's test suite in the worktree

Expect a structured verdict: PASS, FAIL, or LOW_CONFIDENCE.

### On FAIL

Report to Opus with failure reason. Opus decides:

- Re-dispatch to different tool (if attempts < 3)
- Mark as blocked (if all tools tried)
- Refine acceptance criteria and retry same tool

### On LOW_CONFIDENCE

Opus reviews the situation and makes the final call.

### On PASS

Continue to Step 2.

## Step 2: Simplify

Spawn a Sonnet agent in the worktree to run code simplification:

- Focus only on files changed in the diff
- Run the code-simplifier skill if available
- Constraints: must not break tests, must not change behavior

## Step 3: Re-Verify

Spawn another `beacon-reviewer` to confirm simplification preserved correctness.

- Run tests again
- Verify diff is still aligned with acceptance criteria
- If FAIL: revert simplification, use pre-simplification code

## Step 4: Create PR

```bash
cd .beacon/workspaces/<issue-key>
git add -A
git commit -m "<issue-key>: <issue-title>

Closes #<issue-number>

Dispatched by Beacon. Agent: <tool-name>. Attempt: <N>.
Verified by Sonnet reviewer. Tests: passing."

gh pr create \
  --title "<issue-key>: <issue-title>" \
  --body "## Summary\n<from BEACON_RESULT.md>\n\n## Verification\n- Tests: passing\n- Reviewer: PASS\n- Simplified: yes/no\n\nCloses #<number>\n\nDispatched by [Beacon](https://github.com/Maleick/beacon)" \
  --label beacon
```

## Step 5: Monitor PR

Spawn the `beacon-monitor` agent to watch:

- CI check status
- Automated review comments (Copilot, etc.)
- Merge conflicts

### If review comments found

Dispatch a Sonnet agent to address them in the worktree, push fixes to the PR branch.

### Merge decision

- Simple issues: `gh pr merge --squash --auto` immediately after CI passes
- Medium/Complex: Sonnet code review pass required before merge

## Step 6: Cleanup (after merge)

```bash
git worktree remove .beacon/workspaces/<issue-key> --force
gh issue edit <number> --remove-label beacon:in-progress
```

Update `.beacon/state.json`: move issue to completed, increment stats.
