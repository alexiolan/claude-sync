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

echo "---- basic-memory projects ----"
bm_count=$(uvx basic-memory project list 2>/dev/null | wc -l | tr -d ' ')
if [ -n "$bm_count" ] && [ "$bm_count" -gt 0 ] 2>/dev/null; then
  echo "project list lines: $bm_count"
else
  echo "(basic-memory not available or no projects)"
fi
echo "=============================================================="
