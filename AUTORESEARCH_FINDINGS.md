# AutoResearch Findings — Hermes Runtime Hooks Audit

**Date:** 2026-05-04  
**Analyzer:** big-pickle (opencode-zen/autoresearch)  
**Scope:** `hooks/hermes/*.sh`, `config/model-routing.json`, Hermes↔OpenCode integration points  
**Focus areas:** Hook robustness, error handling gaps, missing validation, documentation gaps

---

## Executive Summary

The Hermes runtime hooks (10 scripts) are functional but contain **27 distinct issues** across four categories. **6 items are high-severity** (likely to cause runtime failures or data loss), **13 are medium-severity** (edge cases or fragility), and **8 are low-severity** (polish/documentation).

The most critical problems:
1. The `delegate_task` pathway in `runner.sh` is **stub-only** (echo + status write, no actual task execution)
2. `dispatch.sh` silently continues when `create-worktree.sh` fails (shell substring doesn't inherit `set -e`)
3. Race conditions in workspace status file reads/writes
4. Hardcoded paths (`/Users/maleick/Projects/...`) create brittleness
5. Complete absence of Hermes-specific developer/operator documentation
6. `model-router.sh` has a no-op availability checker rendering fallback tiers unreachable

---

## 1. Hook Robustness (10 issues)

### HIGH: Delegated task pathway is incomplete (runner.sh:90-113)

**File:** `hooks/hermes/runner.sh`  
**Lines:** 90–113  
**Severity:** HIGH  
**Description:** When `HERMES_SESSION_ID` is set, the script writes `DELEGATED` status, echoes instructions to stdout, and exits. No actual `delegate_task` call is made. The 22-line block is effectively a no-op that leaves the workspace in a `DELEGATED` state indefinitely — no subsequent code path resolves it. Subsequent `runner.sh` invocations will skip it because DELEGATED is not QUEUED or RUNNING.  
**Impact:** The Hermes-in-Hermes (delegation) use case is completely non-functional.  
**Recommendation:** Implement `delegate_task` invocation or remove the code path. At minimum, remove the stale comment block and fail with a clear error.

### HIGH: `set -e` doesn't trap substitution failures (dispatch.sh:118)

**File:** `hooks/hermes/dispatch.sh`  
**Line:** 118  
**Severity:** HIGH  
**Description:**  
```bash
FULL_WORKSPACE_PATH=$(bash "$SCRIPT_DIR/../opencode/create-worktree.sh" "$ISSUE_KEY" "autoship/issue-${ISSUE_NUM}")
```
In Bash, `set -e` does **not** propagate from within `$()` command substitution. If `create-worktree.sh` fails (non-zero exit), `FULL_WORKSPACE_PATH` is empty but the script continues — lines 119–123 write workspace files assuming success.  
**Same issue on line 160** (`pr-title.sh` inside substitution).  
**Impact:** Corruption of workspace state; queued workspace with empty worktree path.  
**Recommendation:** Add `|| { echo "create-worktree.sh failed" >&2; exit 1; }` after the substitution.

### MEDIUM: Workspace status file race (runner.sh:52-59, 133-145)

**File:** `hooks/hermes/runner.sh`  
**Lines:** 52–59, 133–145  
**Severity:** MEDIUM  
**Description:** Multiple concurrent `runner.sh` invocations read/write the same `status` file without locking. Between the status check (line 52) and the `printf 'RUNNING\n'` (line 59), another process could change the state. Similarly, after the timeout block, status is re-read without atomicity.  
**Impact:** Double-dispatch of the same issue; status inconsistency.  
**Recommendation:** Use `flock` (as `update-state.sh` does) or a compare-and-swap pattern for status transitions.

### MEDIUM: YAML parsing via grep/awk is fragile (runner.sh:34-39, dispatch.sh:55-61)

**File:** `hooks/hermes/runner.sh:34-39`, `dispatch.sh:55-61`  
**Severity:** MEDIUM  
**Description:** Parsing YAML with `grep 'max_concurrent_children' ~/.hermes/config.yaml | awk '{print $2}'` breaks on:
- Indented config values (common in YAML)
- Comments before the key
- Alternative key names (`max_children`, `concurrent`)
- Quoted vs unquoted values
- Keys with same name in different sections  
**Impact:** MAX defaults silently to 3 even when user has configured a higher value.  
**Recommendation:** Use `yq` (YAML processor) if available, or document the exact YAML format expected.

### MEDIUM: Round-robin wraps incorrectly on empty model list (model-router.sh:38-63)

**File:** `hooks/hermes/model-router.sh`  
**Lines:** 38–63  
**Severity:** MEDIUM  
**Description:** `get_model_from_tier` extracts models with `jq -r ".tiers[$tier_idx].models[].id"`. If the tier has **no models** or `jq` produces no output, the for loop never runs, `next_model` stays empty, and the wrap-around `head -1` on an empty string returns nothing. Callers receive an empty model ID.  
**Impact:** Silent dispatch with empty model ID; downstream failures in `dispatch.sh`.  
**Recommendation:** Validate `models` is non-empty before entering the round-robin loop. Return a hardcoded fallback if empty.

### MEDIUM: `dispatch_with_routing` ignores tier param entirely (model-router.sh:77-106)

**File:** `hooks/hermes/model-router.sh`  
**Lines:** 77–106  
**Severity:** MEDIUM  
**Description:** The `dispatch_with_routing` function accepts `task_type` and `complexity` parameters, uses `complexity` to set `tier` variable, but **then ignores it** — always calls `get_model_from_tier "zen_free"` regardless of complexity value. The `go_paid` tier is only reached via the fallback chain, not directly.  
**Impact:** Complex tasks may be mis-routed to free tier first (by design? but contradicts the parameter semantics).  
**Recommendation:** Either remove the `complexity` parameter or actually use it to select the initial tier.

### MEDIUM: Worktree path with spaces breaks parsing (cleanup-worktrees.sh:82)

**File:** `hooks/hermes/cleanup-worktrees.sh`  
**Line:** 82  
**Severity:** MEDIUM  
**Description:**  
```bash
for wt_info in $(git worktree list --porcelain | grep -E "^worktree " | awk '{print $2}')
```
Word-splitting on spaces will break for any worktree path containing spaces or special characters. `git worktree list --porcelain` outputs one path per line, which could contain spaces.  
**Impact:** Worktree cleanup fails silently for repos with space-containing paths.  
**Recommendation:** Use `while IFS= read -r line` with proper parsing of porcelain format.

### MEDIUM: Hardcoded paths create brittleness (post-merge-cleanup.sh, dispatch.sh)

**Files:** `post-merge-cleanup.sh:12-16`, `dispatch.sh:52`, `runner.sh:72`  
**Severity:** MEDIUM  
**Description:** Multiple scripts hardcode `/Users/maleick/Projects/TextQuest` instead of consistently using `$HERMES_TARGET_REPO_PATH`. `dispatch.sh` line 52 and `runner.sh` line 72 have better patterns (use env var), but `post-merge-cleanup.sh` still hardcodes.  
**Impact:** Fails for any user who clones repos to a different path.  
**Recommendation:** Normalize all path references to use `$HERMES_TARGET_REPO_PATH` (or equivalent) with a documented fallback.

### LOW: `github.com` vs `api.github.com` direct URL (plan-issues.sh:19)

**File:** `hooks/hermes/plan-issues.sh`  
**Line:** 19  
**Severity:** LOW  
**Description:** Uses `curl` to `api.github.com` with `gh auth token` instead of `gh issue list` CLI command. This bypasses `gh` CLI's built-in retry, pagination, and auth handling.  
**Recommendation:** Use `gh issue list --label "$LABELS" --json ...` instead of raw curl.

### LOW: Label scheme mismatch between post-merge-cleanup and AutoShip (post-merge-cleanup.sh:40)

**File:** `hooks/hermes/post-merge-cleanup.sh`  
**Line:** 40  
**Severity:** LOW  
**Description:** Uses `atomic:ready` / `atomic:complete` labels instead of `autoship:*` labels used by the rest of the system.  
**Impact:** Labels won't be managed correctly if the repo uses `autoship:*` label scheme.  
**Recommendation:** Make label names configurable via env vars with AutoShip defaults.

---

## 2. Error Handling Gaps (8 issues)

### HIGH: No-op availability checker (model-router.sh:69-74)

**File:** `hooks/hermes/model-router.sh`  
**Lines:** 69–74  
**Severity:** HIGH  
**Description:**  
```bash
check_model_available() {
  local model="$1"
  # This would check rate limits, quota, etc.
  # For now, assume available
  return 0
}
```
This function is a stub that **always returns success**. The fallback chain in `dispatch_with_routing` (lines 87–106) will never detect that a model is unavailable, so it will never escalate to `go_paid` or `hermes_fallback` tiers.  
**Impact:** If `zen_free` models are rate-limited or exhausted, the system will keep trying them forever instead of falling back.  
**Recommendation:** Implement real availability checks (rate limit headers, quota file, or network test). At minimum, add a configurable retry/cooldown mechanism.

### HIGH: Silent failure when full workspace dir creation fails (dispatch.sh:118-123)

**File:** `hooks/hermes/dispatch.sh`  
**Lines:** 118–123  
**Severity:** HIGH  
**Description:** As noted in robustness, if `create-worktree.sh` fails, the script proceeds to write `started_at`, `status`, `model`, `role` files and `HERMES_PROMPT.md` into a workspace that may have an incomplete or non-existent worktree. The prompt itself (line 147) references `$FULL_WORKSPACE_PATH` which would be empty.  
**Recommendation:** Check `FULL_WORKSPACE_PATH` is non-empty and the directory exists before proceeding.

### MEDIUM: `gh issue view` errors silently swallowed (runner.sh:67-78, dispatch.sh:88-90)

**Files:** `runner.sh:67-78`, `dispatch.sh:88-90`  
**Severity:** MEDIUM  
**Description:** Multiple `gh issue view` calls use `2>/dev/null || echo ""` fallbacks. Failures (rate limits, network errors, 404s) produce no log entry. Error context is lost.  
**Impact:** Silent failures when GitHub API is unreachable — may manifest as empty titles or missing labels.  
**Recommendation:** Log failures to `.autoship/poll.log` or stderr, then fall back.

### MEDIUM: Worktree search fallback doesn't validate git repo (runner.sh:67-68)

**File:** `hooks/hermes/runner.sh`  
**Lines:** 67–68  
**Severity:** MEDIUM  
**Description:**  
```bash
if [[ -n "${HERMES_TARGET_REPO_PATH:-}" ]]; then
  worktree_path=$(git -C "$HERMES_TARGET_REPO_PATH" worktree list --porcelain ...)
```
If `HERMES_TARGET_REPO_PATH` is set but is not a valid git repository, `git -C` will error. The error goes to stderr but isn't caught — the fallback loop runs anyway.  
**Impact:** Unclear error messages; hard to diagnose misconfigured `HERMES_TARGET_REPO_PATH`.  
**Recommendation:** Check `git -C "$HERMES_TARGET_REPO_PATH" rev-parse --git-dir` first.

### MEDIUM: `gh` operations in cleanup-worktrees.sh not guarded (cleanup-worktrees.sh:93-97)

**File:** `hooks/hermes/cleanup-worktrees.sh`  
**Lines:** 93–97  
**Severity:** MEDIUM  
**Description:** Inside the worktree cleanup loop, `gh issue view` is called for each worktree to check if the issue is still active. If `gh` has auth issues, rate limits, or network failures, it silently returns `[]` fallback, causing worktrees for active issues to be deleted.  
**Impact:** Potential deletion of active worktrees during GitHub API outages.  
**Recommendation:** Add a "fail closed" approach — if `gh` errors, skip the worktree (don't delete).

### MEDIUM: Concurrent jq read-modify-write on usage-log.json (model-router.sh:41-44, 110-121)

**File:** `hooks/hermes/model-router.sh`  
**Lines:** 41–44, 110–121  
**Severity:** MEDIUM  
**Description:** The `get_model_from_tier` function reads `usage-log.json` (line 44) and `update_usage_log` writes it (lines 120–121) using a `jq > tmp && mv tmp` pattern without locking. Concurrent model-router.sh invocations can overwrite each other's updates.  
**Impact:** Round-robin state can diverge; models may be skipped or repeated.  
**Recommendation:** Use `flock` (same pattern as `update-state.sh`) for usage log writes.

### MEDIUM: `jq` required but no fallback for state operations (runner.sh, dispatch.sh)

**Files:** `runner.sh:156-158`, `dispatch.sh:78-81`  
**Severity:** MEDIUM  
**Description:** Multiple scripts use `jq` for state file operations without checking if `jq` is installed. While `model-router.sh` checks for `jq`, `dispatch.sh` and `runner.sh` do not when reading `state.json` or finding running workspaces.  
**Impact:** Cryptic errors or silent defaults when `jq` is missing.  
**Recommendation:** Add `jq` availability check with clear error message at the top of each script that uses it.

### LOW: timeout exit code 124 detection is fragile (runner.sh:121)

**File:** `hooks/hermes/runner.sh`  
**Line:** 121  
**Severity:** LOW  
**Description:** The script checks `$exit_code -eq 124` to detect timeout. However, if `hermes chat` itself exits with code 124, this would be a false positive. While unlikely, a more robust approach would compare against the expected timeout duration.  
**Recommendation:** Store the timeout start time and check elapsed wall-clock time instead, or use a more unique exit code convention.

---

## 3. Missing Validation (6 issues)

### MEDIUM: No issue existence validation before worktree creation (dispatch.sh:118)

**File:** `hooks/hermes/dispatch.sh`  
**Line:** 118  
**Severity:** MEDIUM  
**Description:** The script fetches issue metadata (title, body, labels) at lines 88–90, but never validates the issue actually exists on GitHub before creating the worktree (line 118). If `gh issue view` returns empty, the script still creates a worktree with empty title/body.  
**Recommendation:** Validate issue metadata is non-empty before proceeding with worktree creation.

### MEDIUM: `ISSUE_NUM` extraction from key is fragile (runner.sh:63, cronjob-dispatch.sh:30)

**Files:** `runner.sh:63`, `cronjob-dispatch.sh:30`  
**Severity:** MEDIUM  
**Description:**  
```bash
ISSUE_NUM=$(echo "$ISSUE_KEY" | sed 's/issue-//')
```
If `ISSUE_KEY` doesn't start with `issue-` (e.g., bare number or `ISSUE-1234`), `sed` returns the input unchanged. The malformed number could cause downstream failures.  
**Recommendation:** Use `grep -oE '[0-9]+$'` to extract the numeric suffix.

### MEDIUM: Status file modification out-of-band with state.json (runner.sh:59-60, 82-84, 123-124, 148-149)

**File:** `hooks/hermes/runner.sh`  
**Lines:** 59, 82, 84, 123, 124, 148, 149  
**Severity:** MEDIUM  
**Description:** The script writes to the workspace `status` file AND calls `autoship_state_set` (which updates `state.json`) but there's no transactional guarantee between the two. If the script crashes between the two writes, the status and state diverge.  
**Impact:** Stale `state.json` entries; watchdog scripts see inconsistent state.  
**Recommendation:** Always update `state.json` first, then the status file, or better, make the status file authoritative and reconcile from it.

### MEDIUM: No validation of `TASK_TYPE` values (dispatch.sh:42)

**File:** `hooks/hermes/dispatch.sh`  
**Line:** 42  
**Severity:** MEDIUM  
**Description:** `TASK_TYPE="${POSITIONAL[1]:-medium_code}"` accepts any string without validation. Downstream consumers (model-router.sh, prompt generation) may receive unexpected values.  
**Recommendation:** Validate against a known set of task types (`simple_code`, `medium_code`, `complex_code`, `docs`, `review`, etc.).

### MEDIUM: No validation that PR was actually created before closing issue (close-issue.sh:9-19)

**File:** `hooks/hermes/close-issue.sh`  
**Lines:** 9–19  
**Severity:** MEDIUM  
**Description:** The script closes an issue with `gh issue close` after assuming completion, but doesn't verify that a PR was actually created on the associated branch. If the branch push failed but the status was set to COMPLETE, issues could be closed without corresponding code.  
**Recommendation:** Verify PR exists for the branch before closing the issue.

### LOW: Workspace glob expands literally when empty (cleanup-worktrees.sh:47, status.sh:29)

**Files:** `cleanup-worktrees.sh:47`, `status.sh:29`  
**Severity:** LOW  
**Description:** `for ws_dir in "$WORKSPACES_DIR"/issue-*` — if no matching directories exist, the glob remains as a literal `issue-*` string. The `[[ -d "$ws_dir" ]]` guard (line 48) catches this, but there's no log message about the empty state.  
**Recommendation:** Add a `shopt -s nullglob` or an explicit empty-state check with a log message.

---

## 4. Documentation Gaps (6 issues)

### HIGH: No Hermes runtime developer guide

**Severity:** HIGH  
**Description:** There is **no dedicated Hermes runtime documentation**. The `docs/` directory has `API.md`, `OPENCODE_INSTALL.md`, `OPENCODE_PORT_SPEC.md`, `RELEASE.md` — all OpenCode-focused. The `wiki/` directory has `Architecture.md`, `Configuration.md`, `Design-Decisions.md`, `Home.md`, `Troubleshooting.md` — also OpenCode-only. The `ARCHITECTURE.md` at root has a `### Hermes Flow` section and a table, but it's high-level (6 lines).  
**Impact:** Developers and operators cannot understand: how to set up Hermes runtime, how to configure it, how to troubleshoot it, or how the hooks interact.  
**Recommendation:** Create `docs/HERMES_RUNTIME.md` covering:
- Prerequisites and setup
- Environment variable reference
- Hook dependency chain diagram
- Status lifecycle (QUEUED → RUNNING → COMPLETE/BLOCKED/STUCK)
- Cronjob setup instructions
- Troubleshooting common issues

### HIGH: No environment variable reference

**Severity:** HIGH  
**Description:** The following environment variables are used across Hermes hooks with **zero documentation**:

| Variable | Used In | Purpose |
|----------|---------|---------|
| `HERMES_TARGET_REPO` | dispatch.sh, plan-issues.sh, post-merge-cleanup.sh, close-issue.sh | Target GitHub repo |
| `HERMES_TARGET_REPO_PATH` | runner.sh, cleanup-worktrees.sh | Local path to target repo |
| `HERMES_SESSION_ID` | runner.sh, dispatch.sh, setup.sh, status.sh | Hermes session detection |
| `HERMES_CWD` | setup.sh, status.sh | Hermes current working dir |
| `HERMES_PROVIDER` | setup.sh | Hermes provider |
| `HERMES_LABELS` | plan-issues.sh | Issue labels to filter |

**Recommendation:** Add a doc with every env var, its default, example values, and which scripts use it.

### MEDIUM: No function- or parameter-level documentation

**Severity:** MEDIUM  
**Description:** Most Hermes shell functions lack documentation about:
- Parameters (order, types, defaults)
- Return values (stdout output vs exit codes)
- Side effects (which files are modified)
- State transitions (which states are set)

Example: `model-router.sh` exports 4 functions (`get_model_from_tier`, `check_model_available`, `dispatch_with_routing`, `update_usage_log`) but doesn't document their signatures or expected inputs.  
**Recommendation:** Add shell function documentation using consistent `# Usage:` and `# Returns:` conventions (matching `hooks/lib/common.sh` style).

### MEDIUM: Missing script-level "what can go wrong" sections

**Severity:** MEDIUM  
**Description:** Each script should document:
- Prerequisites (which CLIs: gh, jq, git, hermes)
- Exit codes and their meanings
- What happens on partial failure
- Concurrency considerations

Currently, only `runner.sh:1-2` has basic doc. `update-state.sh` is the best-documented but none of the Hermes hooks follow the pattern.  
**Recommendation:** Add a header comment block to each Hermes hook with prerequisites, exit codes, and failure modes.

### MEDIUM: `model-router.sh` functions exported without documentation for consumers

**Severity:** MEDIUM  
**Description:** Lines 124–128 export 4 shell functions with `export -f`. Any script that calls these needs to source this file, but there's no documentation about which functions are safe to call externally, their parameter requirements, or their output format. The `dispatch_with_routing` function is called from `dispatch.sh:96` but the output format (last line of stdout) is an implicit convention.  
**Impact:** Callers that use different parsing will misbehave.  
**Recommendation:** Document the contract for each exported function in the file header.

### LOW: No version/changelog for Hermes hooks

**Severity:** LOW  
**Description:** The `CHANGELOG.md` exists for the overall project but has no Hermes-specific entries. The `config/model-routing.json` has `"version": "2026-05-03"` but the Hermes hooks don't track their own version.  
**Recommendation:** Add a `HERMES_VERSION` variable to each Hermes hook or a single version file.

---

## Configuration File Findings (config/model-routing.json)

### MEDIUM: Config `max_concurrent: 10` conflicts with hooks using 3

**File:** `config/model-routing.json:5`
**Severity:** MEDIUM
**Description:** The config declares `max_concurrent: 10` (with a note about Hermes bottleneck), but Hermes hooks override this to 3 (from `~/.hermes/config.yaml` or default). The config file value is never actually read by Hermes hooks — they use their own YAML parsing from `config.yaml`. There's a discrepancy between the declared and actual limits.
**Recommendation:** Either read `max_concurrent` from `model-routing.json` in Hermes hooks, or remove the note and align the values.

### LOW: `gpt-5.5` listed in hermes_fallback tier but policy forbids `openai/gpt-5.5-fast`

**File:** `config/model-routing.json:43`
**Severity:** LOW
**Description:** Rule 5 says "Never use openai/gpt-5.5-fast" but the `hermes_fallback` tier lists `gpt-5.5` (without `-fast` suffix). It's unclear whether `gpt-5.5` here refers to `openai/gpt-5.5` (allowed) or is a typo for `openai/gpt-5.5-fast` (disallowed). The distinction matters.
**Recommendation:** Be explicit about the model ID. If `openai/gpt-5.5` is intended, add a clarifying note.

---

## Cross-Cutting Concerns

### Mutable workspace files without locking (ALL Hermes hooks)

**Every Hermes hook** that reads/writes workspace status files does so without file locking. The main AutoShip state file (`state.json`) has proper `flock`/`lockf` protection in `update-state.sh`, but the workspace `status` files and `HERMES_PROMPT.md` files are unprotected. Concurrent cronjob invocations of `runner.sh` can corrupt these files.

**Recommendation:** Extend the locking pattern from `update-state.sh` to all workspace file operations, or make the status canonical through `update-state.sh` and remove direct status file writes.

### Inconsistent state machine

The Hermes hooks use states: QUEUED, RUNNING, COMPLETE, BLOCKED, STUCK, DELEGATED, unknown. The OpenCode runtime uses a different set. The `update-state.sh` script knows about both sets but there's overlap and potential confusion:
- `DELEGATED` is unique to Hermes (and as noted, never resolved)
- `unknown` is used as fallback for missing files
- `COMPLETE` vs `completed` — case mismatch between workspace status files and `state.json`

**Recommendation:** Define a single shared state enum for both runtimes. Document the valid transitions.

### ShellCheck compliance

None of the Hermes hooks have been checked with ShellCheck. Common issues observed:
- Unquoted variable expansions (many instances)
- `echo` of untrusted variables (use `printf '%s\n'`)
- Missing `local` declarations for function variables
- `for` loops over command output without `while read`

**Recommendation:** Run `shellcheck hooks/hermes/*.sh` and fix all violations.

---

## Summary Count

| Category | HIGH | MEDIUM | LOW | Total |
|----------|------|--------|-----|-------|
| Hook Robustness | 2 | 6 | 2 | 10 |
| Error Handling | 2 | 5 | 1 | 8 |
| Missing Validation | 0 | 5 | 1 | 6 |
| Documentation Gaps | 2 | 3 | 1 | 6 |
| Configuration | 0 | 1 | 1 | 2 |
| **Total** | **6** | **20** | **6** | **32** |

**Recommendation priority:** Fix the 6 HIGH-severity items first (delegate_task stub, set -e in command substitutions, no-op availability checker, silent worktree failure, missing docs, and env var docs), then address the 5 MEDIUM concurrency/validation items.
