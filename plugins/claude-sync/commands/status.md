---
description: Show claude-sync health — last snapshot age, recent snapshots, repo stats, LaunchAgent state, log tail, and claude-mem db size
argument-hint: ''
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

!`bash "$HOME/claude-sync/status.sh"`

Render the output compactly for the user. It is read-only and never mutates the repo. Call out anything alarming — for example a last-snapshot age older than a few hours, or the `com.alex.claude-backup` LaunchAgent not being loaded. If `~/claude-sync/status.sh` is missing, tell the user to run `/claude-sync:setup` first.
