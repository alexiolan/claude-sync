#!/usr/bin/env bash
# claude-sync backup — encrypted snapshot of the Claude environment to R2.
set -euo pipefail
source "$HOME/claude-sync/env.sh"

restic backup \
  "$HOME/.claude" "$HOME/basic-memory" "$HOME/.basic-memory/config.json" \
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
