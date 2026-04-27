# AutoShip Dependency Graph

## Assessment

**No circular dependencies were found.** The shell script and TypeScript dependency graphs are both directed acyclic graphs (DAGs). However, there is significant tight coupling via hardcoded paths and a hub-and-spoke anti-pattern around state and failure management.

## TypeScript Dependencies

```
src/cli.ts      → (no internal deps)
src/index.ts    → (no internal deps)
plugins/autoship.ts → src/index.ts
```

**Status:** Clean — no cycles, minimal coupling.

## Shell Script Dependencies

### Leaf Nodes (no outgoing script calls)
- `hooks/update-state.sh` — state mutation only
- `hooks/capture-failure.sh` — failure artifact writing only
- `hooks/quota-update.sh` — quota management only
- `hooks/opencode/model-parser.sh` — pure function library
- `hooks/opencode/sync-release.sh` — file copying only
- `hooks/opencode/select-model.sh` — JSON querying only
- `hooks/opencode/create-worktree.sh` — git operations only
- `hooks/opencode/pr-title.sh` — PR metadata only
- `hooks/opencode/lib/common.sh` — shared utilities
- `hooks/opencode/lib/state-lib.sh` — state primitives

### Orchestration Layer (calls leaf nodes)
```
init.sh ──► sync-release.sh, quota-update.sh
setup.sh ──► model-parser.sh (sourced)

dispatch.sh ──► update-state.sh (via autoship_state_set wrapper)
            ──► select-model.sh
            ──► create-worktree.sh
            ──► pr-title.sh

runner.sh ──► update-state.sh (via wrapper)
          ──► capture-failure.sh (via wrapper)
          ──► select-model.sh

create-pr.sh ──► update-state.sh (via wrapper)
             ──► pr-title.sh

verify-result.sh ──► reviewer.sh
reviewer.sh ──► select-model.sh
              ──► capture-failure.sh (via wrapper)

monitor-agents.sh ──► capture-failure.sh (via wrapper)
                  ──► reconcile-state.sh

reconcile-state.sh ──► update-state.sh (via wrapper)

process-event-queue.sh ──► update-state.sh (via wrapper)
                       ──► classify-issue.sh
                       ──► dispatch.sh
                       ──► runner.sh

monitor-prs.sh ──► update-state.sh (via wrapper)
monitor-issues.sh ──► init.sh
```

### Test Scripts
```
smoke-test.sh ──► e2e-package-install-fixture.sh (sourced)
               ──► mock-opencode-models.sh (sourced)
               ──► init.sh
               
test-model-parsing.sh ──► model-parser.sh (sourced)
                       ──► mock-opencode-models.sh (sourced)
                       ──► setup.sh

test-policy.sh ──► Creates isolated test repos with copies of scripts
```

## Key Improvements Made

1. **Created shared utility library** (`hooks/opencode/lib/`)
   - `common.sh` — repo root detection, path constants, command checks, thin wrappers for state/failure operations
   - `state-lib.sh` — locking primitives, safe state reads, running agent counts

2. **Added dependency headers** to all refactored scripts documenting their dependency graph position and leaf callers.

3. **Replaced hardcoded paths with wrapper functions**:
   - `autoship_state_set()` replaces `bash "$REPO_ROOT/hooks/update-state.sh" ...`
   - `autoship_capture_failure()` replaces `bash "$REPO_ROOT/hooks/capture-failure.sh" ...`
   - `autoship_repo_root()` replaces inline `git rev-parse` blocks

4. **Maintained test compatibility** via inline fallbacks — each script carries fallback implementations of the lib functions so copied scripts in isolated test repos continue to work without the lib directory.

## Remaining Structural Debt

- `update-state.sh` remains a 514-line monolith handling locking, state mutation, GitHub label management, and token ledger updates. Consider breaking into focused modules.
- `capture-failure.sh` and `update-state.sh` both read `state.json` independently — shared state-read primitives in `state-lib.sh` are available for future adoption.
- `test-policy.sh` copies 31 test repos and duplicates script files extensively. A helper function to copy scripts with their lib dependencies would reduce fragility.
