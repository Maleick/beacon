# Hermes Agent Prompt — AutoShip Issue #344

## Issue: [M5] Replace CreateRemoteThread + LoadLibraryW with reflective DLL injection

## Labels
enhancement

## Task Type
medium_code

## Model
opencode-zen/nemotron-3-super-free (inherited from ~/.hermes/config.yaml)

## Role
implementer

## Body
## Summary

Replace current injection in `dmft/src/inject/loader.rs` which uses `CreateRemoteThread + LoadLibraryW` (visible in PEB, detected by module enumeration). Implement UDRL-style reflective loader: manual PE mapping, import resolution, relocation handling without calling LoadLibrary.

## Details

The current injection technique is the most commonly detected pattern by anti-cheat systems. A reflective loader manually maps the PE into memory, resolves imports, applies relocations, and calls DllMain — all without the Windows loader ever knowing about the DLL.

**Key implementation steps:**
- Parse PE headers using `goblin` crate
- Allocate memory in target process (use NtCreateSection when available)
- Map sections at correct RVAs
- Resolve imports by walking export tables of loaded DLLs
- Apply base relocations
- Execute TLS callbacks and DllMain

## References
- BokuLoader
- AceLdr
- TitanLdr
- `goblin` crate for PE parsing

## Acceptance Criteria
- DLL loads without PEB entry
- No disk path written to target process
- No LoadLibrary/LoadLibraryW calls during injection

## Instructions
- Work only in this worktree: /Users/maleick/Projects/AutoShip/.autoship/workspaces/issue-344
- Branch: autoship/issue-344
- Implement per acceptance criteria.
- Run project checks: cargo fmt --check, cargo clippy, cargo test (macOS-safe only).
- Commit with conventional format: "feat|fix|docs|refactor(scope): description (#344)".
- **PUSH branch to origin**: 
- **CREATE PR via gh CLI**: 
- **CLOSE issue**: 
- Write HERMES_RESULT.md in worktree root with: status (COMPLETE/BLOCKED/STUCK), files changed, validation results.
- Update .autoship/workspaces/issue-344/status to COMPLETE, BLOCKED, or STUCK.
- If stuck at minute 8, stop and report STUCK with exact status.

## PR Title
PR_TITLE="AutoShip: [M5] Replace CreateRemoteThread + LoadLibraryW with reflective DLL injection (#344)"

## Notes
- Hermes toolsets: terminal, file, web, delegation
- One phase per cron run — resume on next if interrupted
- Use [SILENT] for no-op phases
- Cargo check before cargo test (orchestrator is Windows-only, skip on macOS)
- Never claim Windows/live EQ validation unless actually performed
