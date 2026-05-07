# AutoShip Supervisor Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent OpenCode supervisor loop that keeps AutoShip moving from worker status updates to verification, PR creation, and capacity refill.

**Architecture:** Create one focused hook, `hooks/opencode/supervisor-loop.sh`, that serializes itself with a repo-local lock and runs the existing hooks in order: monitor agents, process the event queue, reconcile state, and run the worker scheduler. The supervisor also clears stale `RUNNING` workspaces that have no live worker PID before asking `runner.sh` to refill capacity.

**Tech Stack:** Bash, jq, GitHub CLI hooks, existing AutoShip OpenCode hook conventions.

---

### Task 1: Add Supervisor Policy Coverage

**Files:**
- Modify: `hooks/opencode/test-policy.sh`

- [ ] **Step 1: Add a failing stale-worker test**

Append a fixture that creates `.autoship/workspaces/issue-101/status` with `RUNNING` but no `worker.pid`, runs `hooks/opencode/supervisor-loop.sh --once`, and asserts the status becomes `STUCK`.

- [ ] **Step 2: Add a failing refill test**

In the same fixture, create a queued workspace and assert `runner.sh` is invoked by writing a small stub runner that records `runner-called`.

- [ ] **Step 3: Run the focused test**

Run: `bash hooks/opencode/test-policy.sh`

Expected before implementation: failure because `hooks/opencode/supervisor-loop.sh` does not exist.

### Task 2: Implement Supervisor Loop

**Files:**
- Create: `hooks/opencode/supervisor-loop.sh`

- [ ] **Step 1: Add CLI flags and defaults**

Support `--once`, `--daemon`, and `--interval SECONDS`. Default interval is `AUTOSHIP_SUPERVISOR_INTERVAL_SECONDS` or `30`.

- [ ] **Step 2: Add a lock guard**

Use `.autoship/supervisor-loop.lock` with `lockf` on Darwin, `flock` where available, and a best-effort fallback. Only one loop may run per repo.

- [ ] **Step 3: Add stale worker cleanup**

For each workspace with `status=RUNNING`, mark it `STUCK` when `worker.pid` is absent, non-numeric, or not live. If `worker.command` exists, require the live PID command to match.

- [ ] **Step 4: Run existing hooks in order**

Each pass runs: `monitor-agents.sh`, `process-event-queue.sh`, `reconcile-state.sh`, `runner.sh`.

- [ ] **Step 5: Add logging**

Write pass start/end and stale cleanup messages to `.autoship/logs/supervisor-loop.log`.

### Task 3: Verify and Publish

**Files:**
- Modify: `hooks/opencode/check.sh` if syntax discovery misses the new hook.

- [ ] **Step 1: Run syntax checks**

Run: `bash -n hooks/opencode/supervisor-loop.sh hooks/opencode/test-policy.sh`

Expected: no output, exit 0.

- [ ] **Step 2: Run focused policy test**

Run: `bash hooks/opencode/test-policy.sh`

Expected: pass.

- [ ] **Step 3: Commit and PR**

Commit on `fix/supervisor-loop`, push to `origin`, and open a PR against `main` in `Maleick/AutoShip`.
