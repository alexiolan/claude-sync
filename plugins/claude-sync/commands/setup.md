---
description: Bootstrap claude-sync on this machine (install restic, write secrets, restore from R2, install the backup LaunchAgent)
argument-hint: ''
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

Run the plugin's own bootstrap script (it works even when `~/claude-sync` does not exist yet on a fresh machine):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```

Notes for presenting the result:
- This command is interactive: it prompts (hidden input) for the R2 Access Key ID, R2 Secret Access Key, and the restic repository passphrase. Never echo those values back.
- Present the script's progress output to the user as-is.
- If the script reports that the restic repository is unreachable, surface the error and remind the user to double-check the three keys/passphrase and their network access — do not retry automatically.
