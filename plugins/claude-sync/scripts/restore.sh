#!/usr/bin/env bash
# claude-sync restore — pull a snapshot from R2 into a staging dir (NON-DESTRUCTIVE).
# Nothing is written into ~/.claude or ~/basic-memory by this script. It restores into
# ~/claude-restore and then PRINTS the exact rsync + reindex steps for the user to run.
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
echo "    (this does NOT touch ~/.claude or ~/basic-memory)"
mkdir -p "$STAGE"

restic restore "$SNAPSHOT" --target "$STAGE"

echo
echo "==> Restore complete. Files are staged under: $STAGE"
echo "    The snapshot preserves absolute paths, so expect:"
echo "      $STAGE/Users/$(id -un)/.claude"
echo "      $STAGE/Users/$(id -un)/basic-memory"
echo "      $STAGE/Users/$(id -un)/.basic-memory/config.json"
echo
echo "==> NEXT STEPS (review, then run manually — nothing below is executed for you):"
echo
echo "  # 1. Place the Claude config (merge, do not delete extras already present):"
echo "  rsync -a \"$STAGE/Users/$(id -un)/.claude/\" \"\$HOME/.claude/\""
echo
echo "  # 2. Place the basic-memory notes:"
echo "  rsync -a \"$STAGE/Users/$(id -un)/basic-memory/\" \"\$HOME/basic-memory/\""
echo
echo "  # 3. Restore the basic-memory config (only the db file is excluded from backups):"
echo "  mkdir -p \"\$HOME/.basic-memory\""
echo "  rsync -a \"$STAGE/Users/$(id -un)/.basic-memory/config.json\" \"\$HOME/.basic-memory/config.json\""
echo
echo "  # 4. Rebuild the basic-memory search index from the restored notes:"
echo "  uvx basic-memory reindex --full   # (or: bm reindex --full)"
echo
echo "==> Done. Review the staged files before placing them if you are unsure."
