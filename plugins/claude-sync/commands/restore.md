---
description: Restore the latest (or a chosen) snapshot from R2 into a staging dir and print non-destructive placement steps
argument-hint: '[--snapshot <id>]'
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

!`bash "$HOME/claude-sync/restore.sh" $ARGUMENTS`

Present the script output to the user. This command is non-destructive: it only restores into the staging dir `~/claude-restore` and prints the exact `rsync` commands the user can run to place the files. Do NOT run those placement commands automatically — let the user review and run them. If `~/claude-sync/restore.sh` is missing, tell the user to run `/claude-sync:setup` first.
