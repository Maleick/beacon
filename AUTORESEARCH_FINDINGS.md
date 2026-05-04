# AutoShip AutoResearch Findings — Kira Vanguard Audit

**Date:** 2026-05-04  
**Researcher:** Kira Vanguard  
**Scope:** AutoShip orchestration plugin — Hermes compatibility, hook robustness, model routing, error handling, documentation gaps  
**Methodology:** Static code analysis of hooks (opencode/ + hermes/), config files, state management, and runtime artifacts. No live issues were available for burn-down.

---

## Executive Summary

AutoShip is a mature multi-runtime orchestration system with strong OpenCode integration and well-structured shell hooks. However, **critical gaps exist in Hermes runtime integration**, model routing consistency, error propagation, and documentation accuracy. Several hooks contain latent bugs that would surface under load or on macOS/BSD systems. No `atomic:ready` issues were found in the target repo, so burn-down was not triggered.

**Severity Distribution:**
- 🔴 **Critical:** 4 findings
- 🟡 **High:** 5 findings
- 🟢 **Medium:** 4 findings
- 🔵 **Low:** 3 findings

---

## 🔴 Critical Findings

### C1. Hermes `model-router.sh` Reads Wrong Config File

**File:** `hooks/hermes/model-router.sh`  
**Line:** 10

```bash
ROUTING_CONFIG="${AUTOSHIP_ROOT}/config/model-routing.json"
```

**Problem:** The Hermes model router hardcodes `config/model-routing.json`, but the OpenCode setup wizard writes to `.autoship/model-routing.json` (see `hooks/opencode/setup.sh:6`). The `config/model-routing.json` file exists and contains a *different* schema (tier-based: `zen_free`, `go_paid`, `hermes_fallback`) while `.autoship/model-routing.json` contains the live OpenCode model pool with `roles`, `pools`, and `models` arrays.

**Impact:** When `dispatch.sh` calls `model-router.sh`, it reads the static tier config and returns models like `opencode-zen/big-pickle`. However, the Hermes runner never actually uses this model — it only writes it to a file and then relies on `delegate_task` or `hermes chat` with no `--model` flag. The model selection is effectively **dead code** for the execution path.

**Fix:** Unify routing config sources or make `model-router.sh` read `.autoship/model-routing.json` with a fallback to `config/model-routing.json`.

---

### C2. Hermes `runner.sh` `delegate_task` Is a No-Op Stub

**File:** `hooks/hermes/runner.sh`  
**Lines:** 103–125

When `HERMES_SESSION_ID` is set, the runner prints:
```
DELEGATE_TASK_READY: issue-N
Worktree: ...
Prompt: ...
Parent agent should now call delegate_task for issue-N
```

Then it writes `DELEGATED` to status and **exits 0**.

**Problem:** The runner does **not** actually invoke `delegate_task`. It assumes the parent Hermes agent will poll the filesystem, detect `DELEGATED` status, read `HERMES_PROMPT.md`, and call `delegate_task`. There is no such polling loop in any hook. In a cronjob context, the task is silently abandoned after the first run.

**Impact:** Hermes dispatch via cronjob is **non-functional**. The issue remains in `DELEGATED` state forever unless a human manually calls `delegate_task`.

**Fix:** Implement actual `delegate_task` invocation in `runner.sh` when `HERMES_SESSION_ID` is present, or document that Hermes dispatch requires a separate polling daemon.

---

### C3. `update-state.sh` `manage_labels()` Uses Brittle `gh label list` + `grep`

**File:** `hooks/update-state.sh`  
**Lines:** 91–101

```bash
if gh label list --repo "$repo_slug" --json name --jq ".[].name" 2>/dev/null | grep -q "^${old_label}$"; then
  gh issue edit "$issue_id" --repo "$repo_slug" --remove-label "$old_label" 2>/dev/null || true
fi
```

**Problem:** `gh label list --json name --jq ".[].name"` outputs one label per line. `grep -q "^${old_label}$"` is an exact match, but if the label contains regex metacharacters (e.g., `autoship:in-progress`), `grep` treats `:` as a regex atom. While `:` is not a special regex character, labels with `+`, `*`, `?`, `[`, `]`, `\`, `^`, `$`, `.` would break. More importantly, **the `grep` is unnecessary** — `gh issue edit --remove-label` is idempotent and returns 0 even if the label is not present. The extra API call to `gh label list` wastes quota.

**Impact:** Wasted GitHub API quota on every state transition. Potential regex misbehavior with exotic labels.

**Fix:** Remove the `gh label list` check. Just run `gh issue edit --remove-label` / `--add-label` directly with `|| true`.

---

### C4. `create-worktree.sh` Removes `.autoship/` Runtime Files from Worktree

**File:** `hooks/opencode/create-worktree.sh`  
**Lines:** 76–85

```bash
rm -f \
  "$WORKSPACE/AUTOSHIP_PROMPT.md" \
  "$WORKSPACE/AUTOSHIP_RESULT.md" \
  ...
```

**Problem:** After `git worktree add`, the script deletes runtime files from the *new worktree directory*. However, `AUTOSHIP_PROMPT.md` and `AUTOSHIP_RESULT.md` are meant to be written *into* the worktree by dispatch/runner. If a previous run left them in the main repo (e.g., due to a bug), they get cleaned. But the script also deletes `model`, `started_at`, and `status` — which are workspace metadata that should persist in `.autoship/workspaces/issue-N/`, not in the worktree itself.

**Impact:** If a hook writes metadata to the worktree root instead of `.autoship/workspaces/`, it gets wiped on the next `create-worktree.sh` call for the same issue key. This is a latent data-loss bug.

**Fix:** Ensure all workspace metadata lives in `.autoship/workspaces/issue-N/` and never in the worktree root. Add a check that refuses to create a worktree if `.autoship/workspaces/issue-N/` already has `RUNNING` status.

---

## 🟡 High Findings

### H1. `runner.sh` Timeout Command Uses `perl` Fallback with Broken Syntax

**File:** `hooks/hermes/runner.sh`  
**Lines:** 133–148

```bash
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  elif command -v perl &>/dev/null; then
    perl_timeout() { perl -e 'alarm shift; exec @ARGV' -- "$@"; }
    TIMEOUT_CMD="perl_timeout"
  else
    echo "Warning: no timeout command found ..."
    TIMEOUT_CMD=""
  fi
fi
```

**Problem:** The `perl_timeout` function definition is inside a subshell (the `elif` branch). When `TIMEOUT_CMD="perl_timeout"` is used later as `$TIMEOUT_CMD 600 ...`, the function is **not exported** and will not be available in the command position. Bash cannot call a function via variable expansion in command position unless it's exported with `export -f`, which is not done.

**Impact:** On macOS without `gtimeout`, the timeout silently fails and the worker runs indefinitely.

**Fix:** Export the function: `export -f perl_timeout`. Or better, use a wrapper script instead of a function.

---

### H2. `select-model.sh` Has Duplicate `if [[ "$LOG" == true ]]` Block

**File:** `hooks/opencode/select-model.sh`  
**Lines:** 64–165

The script defines `JQ_DEFS` and then has:
```bash
if [[ "$LOG" == true ]]; then
  # ... huge jq command ...
  exit 0
fi

# Then later:
if [[ "$LOG" == true ]]; then
  # ... another huge jq command ...
  exit 0
fi

jq -r ... # non-log path
```

**Problem:** The first `if [[ "$LOG" == true ]]` block (lines ~64–112) is **unreachable** because the second block (lines ~114–165) shadows it. The first block uses `--slurpfile history "$HISTORY_FILE" --slurpfile circuit "$CIRCUIT_FILE"` which are not defined in the first block's scope (they are defined later). This is a copy-paste error.

**Impact:** The `--log` flag produces output from the second block, but the first block's richer routing log format is never executed. Model selection logging is incomplete.

**Fix:** Remove the first unreachable `if [[ "$LOG" == true ]]` block (lines 64–112).

---

### H3. `dispatch.sh` (Hermes) Does Not Validate `HERMES_TARGET_REPO` Exists

**File:** `hooks/hermes/dispatch.sh`  
**Lines:** 83–88

```bash
TITLE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title --jq '.title' 2>/dev/null || echo "Issue $ISSUE_NUM")
```

**Problem:** If `HERMES_TARGET_REPO` is set to a non-existent repo or the user lacks access, `gh issue view` fails silently and the title becomes `"Issue $ISSUE_NUM"`. The dispatch proceeds with a stub title, creating a PR with a meaningless title later.

**Impact:** Poor PR quality. No early failure for bad config.

**Fix:** Add explicit validation:
```bash
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  echo "Error: cannot access repo $REPO" >&2
  exit 1
fi
```

---

### H4. `auto-prune.sh` Uses `ls -1td ... | tail -r` Which Is macOS-Only

**File:** `hooks/hermes/auto-prune.sh`  
**Lines:** 147–148, 178–179

```bash
for wt in $(ls -1td "$WORKTREE_BASE"/issue-* 2>/dev/null | tail -r); do
```

**Problem:** `tail -r` reverses lines. This is a **BSD/macOS-specific** flag. On Linux, `tail` does not have `-r`. The script will fail on Linux with `tail: invalid option -- 'r'`.

**Impact:** Auto-prune is **non-portable** and will break in CI or Docker (Linux).

**Fix:** Replace with portable `tac` (GNU) or `sort -r`:
```bash
ls -1td "$WORKTREE_BASE"/issue-* 2>/dev/null | sort -r
```

---

### H5. `gh-retry.sh` Does Not Retry on HTTP 401/403 (Rate Limit vs Auth)

**File:** `hooks/opencode/gh-retry.sh`  
**Lines:** 49–67

The retry logic classifies exit code 1 as retryable unless the output contains `not found|already exists|permission denied|unauthorized`. However, GitHub CLI returns HTTP 401/403 as exit code 1 with messages like `HTTP 401: Bad credentials` or `HTTP 403: API rate limit exceeded`. The latter **should be retried** with backoff, but the script treats it as non-retryable because it contains `unauthorized`/`permission denied`.

**Impact:** Transient rate limits (HTTP 403 with `rate limit exceeded`) cause immediate failure instead of retry.

**Fix:** Distinguish between authentication errors (401, bad credentials) and rate limits (403 with `rate limit` or `quota`). Only skip retry for the former.

---

## 🟢 Medium Findings

### M1. `check.sh` Does Not Check `hooks/hermes/*.sh` Syntax

**File:** `hooks/opencode/check.sh`  
**Lines:** 87–113

The syntax check iterates over `$HOOKS_DIR/*.sh` and `$HOOKS_DIR/opencode/*.sh`, but **never checks `$HOOKS_DIR/hermes/*.sh`**.

**Impact:** Hermes hook syntax errors are only caught at runtime.

**Fix:** Add:
```bash
for script in "$HOOKS_DIR/hermes"/*.sh; do
  [[ -f "$script" ]] || continue
  ...
done
```

---

### M2. `cleanup-worktrees.sh` Phase 2 `git worktree list` Parsing Is Fragile

**File:** `hooks/hermes/cleanup-worktrees.sh`  
**Lines:** 85–95

```bash
for wt_info in $(git worktree list --porcelain 2>/dev/null | grep -E "^worktree " | awk '{print $2}'); do
  if [[ ! "$wt_info" =~ \.worktrees/issue-[0-9]+$ ]]; then
    continue
  fi
```

**Problem:** The `grep -E "^worktree " | awk '{print $2}'` pattern assumes the worktree path does not contain spaces. If `HERMES_TARGET_REPO_PATH` contains spaces (e.g., `/Users/name/My Projects/TextQuest`), `awk '{print $2}'` truncates the path.

**Impact:** Worktrees with spaces in their path are never cleaned up.

**Fix:** Use `cut -d' ' -f2-` or a proper while-read loop:
```bash
git worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
  if [[ "$line" =~ ^worktree\ (.+) ]]; then
    wt_path="${BASH_REMATCH[1]}"
    ...
  fi
done
```

---

### M3. `reconcile-state.sh` `cd "$TARGET_REPO"` Is Unconditional After Directory Check

**File:** `hooks/opencode/reconcile-state.sh`  
**Lines:** 140–142

```bash
cd "$TARGET_REPO" 2>/dev/null && git worktree prune 2>/dev/null || true
```

**Problem:** `$TARGET_REPO` is set to `${HERMES_TARGET_REPO_PATH:-$HOME/Projects/TextQuest}`. If the directory does not exist, `cd` fails and `git worktree prune` runs in the AutoShip repo instead. This is harmless but confusing.

**Fix:** Only run `git worktree prune` if the directory exists and is a git repo:
```bash
if [[ -d "$TARGET_REPO/.git" ]]; then
  (cd "$TARGET_REPO" && git worktree prune)
fi
```

---

### M4. `verify-result.sh` `run_test_command` Has Overly Restrictive Character Validation

**File:** `hooks/opencode/verify-result.sh`  
**Lines:** 47–53

```bash
for part in "${command_parts[@]}"; do
  if [[ ! "$part" =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
    fail "test command contains unsupported characters"
  fi
done
```

**Problem:** The regex rejects valid shell characters like `>`, `|`, `;`, `&`, `"`, `'`, `(`, `)`, `[`, `]`, `{`, `}`, `` ` ``, `$`, `*`, `?`, `~`, `!`. This prevents test commands like `cargo test 2>&1 | tee log.txt` or `bash -c "echo hello"`.

**Impact:** Complex test commands are rejected even when safe.

**Fix:** Remove the character whitelist or replace it with a blacklist of dangerous characters (e.g., `;`, `&`, `|`, `` ` ``, `$()` only if they contain unquoted strings). Alternatively, accept that test commands come from trusted config and skip validation.

---

## 🔵 Low Findings

### L1. `AUTOSHIP.md` Claims OpenCode Is the "Only Worker Runtime"

**File:** `AUTOSHIP.md`  
**Line:** 6

```yaml
routing:
  research: [opencode]
  docs: [opencode]
  ...
```

**Problem:** The front matter and prose claim "OpenCode is the only worker runtime", but the entire `hooks/hermes/` directory and `README.md` describe a Hermes runtime. This is a documentation inconsistency.

**Fix:** Update `AUTOSHIP.md` to acknowledge Hermes as a secondary runtime, or move Hermes docs to a separate file.

---

### L2. `README.md` `max_concurrent` Values Are Out of Sync with Config

**File:** `README.md`  
**Lines:** ~45–50

The ASCII diagram shows:
```
│  WORKER DISPATCH       15 ACTIVE MAX     │
│  HERMES RUNTIME        3 ACTIVE MAX      │
```

But `config/model-routing.json` says:
```json
"max_concurrent": 10,
"notes": "max_concurrent reduced from 15 to 10 ..."
```

And `.autoship/config.json` says:
```json
"maxConcurrentAgents": 15
```

**Impact:** Confusing for operators trying to tune concurrency.

**Fix:** Align all sources to the same value (recommend 10 to match the Hermes delegation bottleneck note).

---

### L3. `model-router.sh` `update_usage_log` Never Called

**File:** `hooks/hermes/model-router.sh`  
**Lines:** 127–143

The `update_usage_log` function is defined and exported, but **no caller in the codebase invokes it**. The `.autoship/usage-log.json` file is referenced in `dispatch.sh` (line 109: `echo "..." >> "$AUTOSHIP_DIR/logs/model-selection.log"`) but the structured usage log is never written.

**Impact:** The round-robin rotation in `get_model_from_tier` always starts from the first model because `last_used` is never updated.

**Fix:** Call `update_usage_log "$model"` in `dispatch.sh` after model selection, or remove the unused function.

---

## Fixes Applied

No fixes were applied during this research phase. The findings are documented for prioritization and burn-down. The following fixes are recommended in priority order:

1. **C2** — Implement actual `delegate_task` invocation in `runner.sh` (or document limitation)
2. **C1** — Unify model routing config between Hermes and OpenCode
3. **H1** — Fix `perl_timeout` function export for macOS
4. **H4** — Replace `tail -r` with portable `sort -r` in `auto-prune.sh`
5. **C3** — Remove redundant `gh label list` check in `update-state.sh`
6. **H2** — Remove duplicate `--log` block in `select-model.sh`
7. **H5** — Distinguish rate-limit 403 from auth 401 in `gh-retry.sh`
8. **M1** — Add `hooks/hermes/*.sh` to `check.sh` syntax checks
9. **M2** — Fix space-in-path handling in `cleanup-worktrees.sh`
10. **C4** — Clarify workspace metadata vs worktree root file locations

---

## GitHub Issues Created

No issues were created because the target repo (`Maleick/AutoShip`) had no open issues at the time of research, and the `atomic:ready` label query returned empty results. The findings above should be filed as:

| Issue | Title | Label |
|-------|-------|-------|
| #TBD | Hermes runner `delegate_task` is a no-op stub | `bug`, `hermes` |
| #TBD | Hermes `model-router.sh` reads stale `config/model-routing.json` | `bug`, `hermes`, `routing` |
| #TBD | `update-state.sh` wastes API quota on `gh label list` | `bug`, `performance` |
| #TBD | `create-worktree.sh` deletes workspace metadata from worktree root | `bug`, `data-loss` |
| #TBD | `perl_timeout` function not exported in Hermes runner | `bug`, `macos`, `timeout` |
| #TBD | `select-model.sh` has unreachable duplicate `--log` block | `bug`, `cleanup` |
| #TBD | `auto-prune.sh` uses non-portable `tail -r` | `bug`, `linux`, `portability` |
| #TBD | `gh-retry.sh` treats rate-limit 403 as non-retryable | `bug`, `retry`, `github-api` |
| #TBD | `check.sh` skips Hermes hook syntax validation | `bug`, `hermes`, `qa` |
| #TBD | `cleanup-worktrees.sh` breaks on paths with spaces | `bug`, `portability` |
| #TBD | `verify-result.sh` test command whitelist is too restrictive | `bug`, `ux` |
| #TBD | Documentation: `AUTOSHIP.md` and `README.md` concurrency values out of sync | `docs`, `cleanup` |

---

## Recommendations

1. **Hermes Runtime Maturity:** The Hermes hooks are significantly less mature than OpenCode hooks. Consider marking Hermes support as "beta" in documentation until `delegate_task` invocation and model routing are fixed.

2. **Model Routing Unification:** Maintain a single source of truth for model routing. The current split between `config/model-routing.json` (static tiers) and `.autoship/model-routing.json` (live OpenCode pool) causes confusion. Merge into one file with a `runtime` field.

3. **macOS/Linux Portability Audit:** Several hooks (`auto-prune.sh`, `update-state.sh` date parsing, `runner.sh` timeout) have macOS-specific code that breaks on Linux. Run `check.sh` in a Linux CI container to catch these.

4. **Error Handling Telemetry:** The failure capture system (`capture-failure.sh`) is well-designed but underutilized. Ensure all hooks call `autoship_capture_failure` on non-zero exits, not just the runner.

5. **State File Locking:** The `flock` / `lockf` dual-path locking in `update-state.sh` is clever but the `lockf` path has not been tested in CI. Add a test that simulates concurrent state updates.

6. **Documentation Sync:** Establish a single source of truth for `max_concurrent` values and runtime capabilities. The `README.md`, `AUTOSHIP.md`, `config/model-routing.json`, and `.autoship/config.json` currently disagree.

---

*End of findings. Ready for burn-down prioritization.*
