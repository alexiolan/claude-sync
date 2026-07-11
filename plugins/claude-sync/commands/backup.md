---
description: Force an immediate encrypted snapshot of the Claude environment to R2
argument-hint: ''
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

!`bash "$HOME/claude-sync/backup.sh"`

Present the restic output to the user. The final line of a successful run reports the new snapshot ID and the files/blobs added. If `~/claude-sync/backup.sh` is missing, tell the user to run `/claude-sync:setup` first.
