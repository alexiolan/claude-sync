#!/usr/bin/env bash
# claude-sync backup — encrypted snapshot of the Claude environment to R2.
set -euo pipefail
source "$HOME/claude-sync/env.sh"

CM_DB="$HOME/.claude-mem/claude-mem.db"
if [ -f "$CM_DB" ]; then
  sqlite3 "$CM_DB" ".backup '$HOME/.claude-mem/claude-mem.snapshot.db'" \
    || echo "warning: claude-mem snapshot failed" >&2
fi

restic backup \
  "$HOME/.claude" "$HOME/.claude-mem" \
  --exclude-file "$HOME/claude-sync/excludes.txt" \
  --tag claude-env "$@"

# Heavier prune + integrity check at most ~once/day (skip if done in last 20h).
LAST="$HOME/.config/claude-sync/.last-prune"
now=$(date +%s)
last=$( [ -f "$LAST" ] && stat -f %m "$LAST" 2>/dev/null || echo 0 )
if [ $(( now - last )) -gt 72000 ]; then
  restic forget --prune --keep-daily 14 --keep-weekly 8 --keep-monthly 12
  restic check
  touch "$LAST"
fi
