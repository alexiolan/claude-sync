#!/usr/bin/env bash
# claude-sync restore — pull a snapshot from R2 into a staging dir (NON-DESTRUCTIVE).
# Nothing is written into ~/.claude or ~/.claude-mem by this script. It restores into
# ~/claude-restore and then PRINTS the exact rsync steps for the user to run.
#
# Usage:
#   restore.sh                 # restore the latest snapshot
#   restore.sh --snapshot <id> # restore a specific snapshot id
set -euo pipefail

source "$HOME/claude-sync/env.sh"

SNAPSHOT="latest"
if [ "${1:-}" = "--snapshot" ]; then
  [ -n "${2:-}" ] || { echo "error: --snapshot requires a snapshot id" >&2; exit 2; }
  SNAPSHOT="$2"
elif [ -n "${1:-}" ]; then
  echo "error: unknown argument '$1' (expected: --snapshot <id>)" >&2
  exit 2
fi

STAGE="$HOME/claude-restore"

echo "==> Restoring snapshot '$SNAPSHOT' into staging dir: $STAGE"
echo "    (this does NOT touch ~/.claude or ~/.claude-mem)"
mkdir -p "$STAGE"

restic restore "$SNAPSHOT" --target "$STAGE"

echo
echo "==> Restore complete. Files are staged under: $STAGE"
echo "    The snapshot preserves absolute paths, so expect:"
echo "      $STAGE/Users/$(id -un)/.claude"
echo "      $STAGE/Users/$(id -un)/.claude-mem"
echo
echo "==> NEXT STEPS (review, then run manually — nothing below is executed for you):"
echo
echo "  # 1. Place the Claude config (merge, do not delete extras already present):"
echo "  rsync -a \"$STAGE/Users/$(id -un)/.claude/\" \"\$HOME/.claude/\""
echo
echo "  # 2. Place claude-mem (snapshot DB; chroma is rebuilt by claude-mem from SQLite):"
echo "  mkdir -p \"\$HOME/.claude-mem\""
echo "  rsync -a \"$STAGE/Users/$(id -un)/.claude-mem/\" \"\$HOME/.claude-mem/\""
echo "  [ -f \"\$HOME/.claude-mem/claude-mem.db\" ] || mv \"\$HOME/.claude-mem/claude-mem.snapshot.db\" \"\$HOME/.claude-mem/claude-mem.db\""
echo
echo "==> Done. Review the staged files before placing them if you are unsure."
