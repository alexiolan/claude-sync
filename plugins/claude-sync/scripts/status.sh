#!/usr/bin/env bash
# claude-sync status — READ-ONLY health overview. Never mutates the repo.
# Deliberately NOT using `set -e`: a missing log, an unreachable repo, or an
# unloaded LaunchAgent must not abort the rest of the report.
set -uo pipefail

source "$HOME/claude-sync/env.sh" 2>/dev/null || {
  echo "error: cannot source ~/claude-sync/env.sh — run /claude-sync:setup first" >&2
  exit 1
}

LOG="$HOME/claude-sync/backup.log"

echo "===================== claude-sync status ====================="
echo "repo: ${RESTIC_REPOSITORY:-<unset>}"
echo

echo "---- last snapshot ----"
last_json=$(restic snapshots latest --json 2>/dev/null)
last_time=$(printf '%s' "$last_json" | sed -n 's/.*"time":"\([^"]*\)".*/\1/p' | head -1)
if [ -n "$last_time" ]; then
  echo "latest snapshot time: $last_time"
  last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${last_time%%.*}" "+%s" 2>/dev/null || echo "")
  if [ -n "$last_epoch" ]; then
    now=$(date +%s)
    age=$(( now - last_epoch ))
    printf "age: %dh %dm\n" $(( age / 3600 )) $(( (age % 3600) / 60 ))
  fi
else
  echo "(could not read latest snapshot — repo unreachable or empty)"
fi
echo

echo "---- recent snapshots ----"
restic snapshots --latest 5 2>&1 || echo "(restic snapshots failed)"
echo

echo "---- repo size (raw data) ----"
restic stats --mode raw-data 2>&1 || echo "(restic stats failed)"
echo

echo "---- LaunchAgent ----"
if launchctl list 2>/dev/null | grep -q claude-backup; then
  launchctl list 2>/dev/null | grep claude-backup
else
  echo "com.alex.claude-backup: NOT loaded"
fi
echo

echo "---- backup.log (tail) ----"
if [ -f "$LOG" ]; then
  tail -n 15 "$LOG"
else
  echo "(no log at $LOG yet)"
fi
echo

echo "---- claude-mem ----"
if [ -f "$HOME/.claude-mem/claude-mem.db" ]; then
  du -h "$HOME/.claude-mem/claude-mem.db" | cut -f1 | sed 's/^/db size: /'
else
  echo "(no ~/.claude-mem/claude-mem.db)"
fi
echo "=============================================================="
