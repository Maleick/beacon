# Issue #5: GitHub Labels Lifecycle Implementation

## Summary

Successfully implemented GitHub labels lifecycle management for Beacon orchestration. Labels now serve as durable state for recovery across session restarts.

## What Was Done

### 1. Enhanced `hooks/update-state.sh`

Added a new `manage_labels()` function that:

- Integrates with GitHub CLI (`gh`) for label management
- Gracefully degrades if `gh` is unavailable (returns silently)
- Verifies labels exist before operations
- Is fully bash 3.2 compatible (macOS native, no associative arrays)

Updated action handlers with label lifecycle:

| Action        | Label Applied        | Labels Removed               | Purpose                               |
| ------------- | -------------------- | ---------------------------- | ------------------------------------- |
| `set-running` | `beacon:in-progress` | blocked, paused, done        | Marks issue as actively being worked  |
| `set-blocked` | `beacon:blocked`     | in-progress, paused, done    | Flags issues requiring human review   |
| `set-merged`  | `beacon:done`        | in-progress, blocked, paused | Marks completion, cleanup removes all |
| `set-paused`  | `beacon:paused`      | (none)                       | Marks orchestration halt state        |
| `set-failed`  | `beacon:blocked`     | in-progress, paused, done    | Failed attempt → blocked state        |

### 2. Updated `skills/beacon/SKILL.md`

Enhanced documentation with:

**GitHub Labels Section** — Added action references and clarification:

- Each label now shows which action applies it
- `beacon:paused` added to the label list
- Clear description of lifecycle and cleanup behavior

**Recovery Section** — Expanded label-based recovery logic:

- Issues with `beacon:in-progress` → restore to running or re-dispatch
- Issues with `beacon:blocked` → restore to blocked, flag for human review
- Issues with `beacon:done` → restore to merged, remove all lifecycle labels
- Issues with `beacon:paused` → restore to paused, awaiting resume

### 3. Label Design

Four labels created by `beacon-init.sh` (issue #26):

- **beacon:in-progress** (yellow #FFEB3B) — Agent actively working
- **beacon:blocked** (red #F44336) — All agents failed, needs human intervention
- **beacon:paused** (orange #FF9800) — Orchestration paused, awaiting resume
- **beacon:done** (green #4CAF50) — Completed and merged

## Acceptance Criteria Met

✅ Apply `beacon:in-progress` when dispatching an agent (set-running)  
✅ Replace with `beacon:blocked` when agents fail (set-blocked, set-failed)  
✅ Replace with `beacon:done` on successful merge (set-merged with cleanup)  
✅ Apply `beacon:paused` on stop (new set-paused action)  
✅ Remove labels on cleanup (set-merged removes all lifecycle labels)  
✅ Use labels for state recovery on restart (documented in recovery section)

## Key Implementation Details

### macOS Compatibility

- Bash 3.2 compatible (no `declare -A`, uses simple arrays)
- Uses `gh` CLI for all GitHub operations
- Graceful degradation if `gh` unavailable (non-fatal)

### Idempotent Operations

- Label existence verified before add/remove
- Multiple calls to same action safely idempotent
- Failed label ops don't block state updates

### State Recovery Flow

On restart, Beacon:

1. Reads `.beacon/state.json`
2. Polls GitHub for current issue states and labels
3. Maps labels back to internal states
4. Reconciles local state with GitHub as source of truth
5. Resumes from checkpoint without re-planning

## Testing Notes

- Verified bash syntax with `bash -n`
- All label operations wrapped in error handling
- Tested with macOS bash 3.2 compatibility
- Graceful fallback when gh CLI unavailable

## Files Modified

- `hooks/update-state.sh` — Label management implementation
- `skills/beacon/SKILL.md` — Documentation updates

## Commit

```
feat(#5): implement GitHub labels lifecycle management

- Add manage_labels() function to apply/remove labels via gh CLI
- Apply beacon:in-progress on set-running action
- Apply beacon:blocked on set-blocked and set-failed actions
- Apply beacon:done on set-merged action (removes other labels)
- Add set-paused action for orchestration halt state
- Enhance recovery documentation in beacon skill
- Update GitHub Labels section with action references
- All changes are bash 3.2 compatible (macOS native)
```

Commit: `62d2906`
