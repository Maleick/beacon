#!/usr/bin/env bash
# Post-merge cleanup: remove worktrees after PR is merged
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISSUE_NUM="${1:?Issue number required}"
REPO="${HERMES_TARGET_REPO:-Maleick/TextQuest}"

echo "=== Post-merge cleanup for issue #$ISSUE_NUM ==="

# 1. Remove local worktree
wt_path="/Users/maleick/Projects/TextQuest.worktrees/issue-${ISSUE_NUM}"
if [[ -d "$wt_path" ]]; then
  echo "Removing worktree: $wt_path"
  cd /Users/maleick/Projects/TextQuest
  git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path" 2>/dev/null || true
  git worktree prune
  echo "✅ Worktree removed"
else
  echo "No worktree found at $wt_path"
fi

# 2. Remove AutoShip workspace
ws_path="/Users/maleick/Projects/AutoShip/.autoship/workspaces/issue-${ISSUE_NUM}"
if [[ -d "$ws_path" ]]; then
  echo "Removing workspace: $ws_path"
  rm -rf "$ws_path"
  echo "✅ Workspace removed"
fi

# 3. Clean up branch
branch="autoship/issue-${ISSUE_NUM}"
cd /Users/maleick/Projects/TextQuest
if git branch | grep -q "$branch"; then
  git branch -D "$branch" 2>/dev/null || true
  echo "✅ Local branch removed"
fi

# 4. Update issue labels
gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label atomic:ready --add-label atomic:complete 2>/dev/null || true

echo "=== Cleanup complete ==="
