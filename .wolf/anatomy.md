# anatomy.md

> Auto-maintained by OpenWolf. Last scanned: 2026-04-12T07:52:19.022Z
> Files: 45 tracked | Anatomy hits: 0 | Misses: 0

## ./

- `.gitignore` — Git ignore rules (~34 tok)
- `BEACON_SPEC.md` — Beacon Specification v2 → v3 (~4091 tok)
- `BEACON_V3_ARCHITECTURE.md` — Beacon v3 Architecture — Advisor + Monitor Pattern (~4450 tok)
- `CLAUDE.md` — OpenWolf (~949 tok)
- `LICENSE` — Project license (~284 tok)
- `README.md` — Project documentation (~1716 tok)
- `VERSION` — Semver release tag (e.g. v1.0.0), bumped on every change (~2 tok)

## .beacon/

- `config.json` (~1 tok)
- `quota.json` (~83 tok)
- `state.json` (~195 tok)

## .claude-plugin/

- `marketplace.json` (~169 tok)
- `plugin.json` (~158 tok)

## .claude/

- `settings.json` (~441 tok)
- `settings.local.json` (~75 tok)

## .claude/rules/

- `openwolf.md` (~313 tok)

## agents/

- `haiku-triage.md` — Beacon Event Triage Agent (~846 tok)
- `monitor.md` — DEPRECATED — v2 artifact (~1702 tok)
- `reviewer.md` — Structured Input (~879 tok)

## commands/

- `beacon.md` (~226 tok)
- `plan.md` — Step 1: Prerequisite Checks (~380 tok)
- `start.md` — Step 1: Prerequisite Checks (~307 tok)
- `status.md` (~70 tok)
- `stop.md` — Phase 0: Kill Monitors + Drain Event Queue (~345 tok)

## hooks/

- `beacon-activate.sh` — SessionStart hook: runs beacon-init.sh silently then injects system context with version + command hints (~268 tok)
- `beacon-init.sh` (~2677 tok)
- `check-completion.sh` (~460 tok)
- `cleanup-worktree.sh` (~846 tok)
- `detect-tools.sh` (~1543 tok)
- `monitor-agents.sh` — monitor-agents.sh — Watch .beacon/workspaces/\*/pane.log for agent status words. (~986 tok)
- `monitor-issues.sh` — monitor-issues.sh — Poll GitHub for new and closed issues. (~658 tok)
- `monitor-prs.sh` — monitor-prs.sh — Watch Beacon PRs for CI status, conflicts, and merges. (~1054 tok)
- `quota-update.sh` (~2063 tok)
- `sweep-stale.sh` (~1197 tok)
- `update-state.sh` — Declares to (~1576 tok)

## skills/beacon-discord-commands/

- `SKILL.md` — Beacon Discord Command Channel (~1485 tok)

## skills/beacon-discord-webhook/

- `SKILL.md` — Beacon Discord Webhook Protocol (~1973 tok)

## skills/beacon-dispatch/

- `SKILL.md` — Beacon Dispatch Protocol — v3 (~2989 tok)

## skills/beacon-poll/

- `SKILL.md` — Beacon Poll Protocol (~2466 tok)

## skills/beacon-status/

- `SKILL.md` — Beacon Status (~1151 tok)

## skills/beacon-verify/

- `SKILL.md` — Beacon Verification Pipeline (~1440 tok)

## skills/beacon/

- `SKILL.md` — Beacon Orchestration Protocol — v3 (Sonnet Executor + Opus Advisor) (~3604 tok)

## wiki/

- `Architecture.md` — Architecture (~1701 tok)
- `Configuration.md` — Configuration (~1304 tok)
- `Design-Decisions.md` — Design Decisions (~1977 tok)
- `Troubleshooting.md` — Troubleshooting (~1192 tok)
