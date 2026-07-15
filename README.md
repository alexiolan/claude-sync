# claude-sync

Encrypted, off-site backup and restore for your Claude Code environment.

`claude-sync` takes encrypted [restic](https://restic.net) snapshots of your Claude
config and your [basic-memory](https://github.com/basicmachines-co/basic-memory) notes
and pushes them to a private Cloudflare R2 bucket. On a fresh laptop, one command pulls
everything back and re-wires your machine.

> **Platform support (WIP):** claude-sync currently runs on **macOS only**. Native
> **Windows** support is designed but not yet implemented — the audit findings and the
> agreed plan (native Windows + a shared Python core, no WSL2) live in
> [`docs/cross-platform-support.md`](docs/cross-platform-support.md). Start there
> before touching Windows.

## What gets backed up

- `~/.claude` (settings, projects, memory, agents, commands — minus caches/credentials)
- `~/basic-memory` (all your notes, as plain Markdown)
- `~/.basic-memory/config.json` (the basic-memory project registry)

Excluded (see `scripts/excludes.txt`): the plugin cache, `.credentials.json`, statsig,
shell snapshots, todos, the SQLite index DBs, and any `*.log`. The index DB is excluded
on purpose — it is rebuilt from the Markdown on restore.

**Repo:** restic over S3 to your private Cloudflare R2 bucket
(`s3:https://<account>.r2.cloudflarestorage.com/<bucket>`, `AWS_DEFAULT_REGION=auto`).

---

## The "4 keys" you must keep safe

restic backups are useless without the credentials to read them. There are **four**
secrets. Store them in a password manager AND in physical escrow (sealed envelope / second
manager) — if you lose the restic passphrase, the data is unrecoverable by anyone.

| # | Secret | Where it lives on a set-up machine |
|---|--------|------------------------------------|
| 1 | **R2 bucket URL**           | `~/.config/claude-sync/r2-repo-url` (chmod 600) |
| 2 | **R2 Access Key ID**        | `~/.config/claude-sync/r2-keys.sh` (chmod 600) |
| 3 | **R2 Secret Access Key**    | `~/.config/claude-sync/r2-keys.sh` (chmod 600) |
| 4 | **restic repo passphrase**  | `~/.config/claude-sync/restic-pass` (chmod 600) |

All four are prompted (hidden input) by `/claude-sync:setup` and written to
`~/.config/claude-sync/` (chmod 600). None are stored in this repo or printed by any command.

---

## Install

Add the marketplace and install the plugin:

```
/plugin marketplace add <owner>/claude-sync-plugin
/plugin install claude-sync@claude-sync-marketplace
```

This registers the four slash commands, the session-capture hooks, and the global
`basic-memory` MCP server.

---

## Fresh-laptop runbook

You just got a new machine and want everything back:

1. **Install the plugin** (above).
2. **Run setup:**
   ```
   /claude-sync:setup
   ```
   There is **no Google / OAuth step** — this is a private R2 bucket. Setup will:
   - install Homebrew (if missing), `restic`, `uv`, and `basic-memory`;
   - copy the runtime into `~/claude-sync`;
   - **prompt (hidden input) for the R2 bucket URL, R2 Access Key, R2 Secret, and the
     restic passphrase** — the four secrets above;
   - write them to the `chmod 600` files in `~/.config/claude-sync/`;
   - verify it can read the (already-existing) repo;
   - `restic restore latest` into `~/.claude` and `~/basic-memory`;
   - recreate `~/.basic-memory/config.json`, re-register each restored project by its
     local path, and run `basic-memory reindex --full`;
   - install + load the `com.alex.claude-backup` LaunchAgent (runs at load, then every 2h).
3. **Restart Claude Code** so the restored config and MCP server load.

That's it — your sessions, memory, and notes are back, and ongoing backups are already
scheduled.

---

## Command reference

| Command | What it does |
|---------|--------------|
| `/claude-sync:setup`   | First-run bootstrap on a new machine (interactive). Runs the plugin's own `scripts/setup.sh`. |
| `/claude-sync:backup`  | Force an immediate snapshot now. Runs `~/claude-sync/backup.sh`. |
| `/claude-sync:restore` | Restore latest (or `--snapshot <id>`) into the staging dir `~/claude-restore` and print non-destructive placement steps. Runs `~/claude-sync/restore.sh`. |
| `/claude-sync:status`  | Read-only health check: last-snapshot age, recent snapshots, repo size, LaunchAgent state, log tail, basic-memory project count. Runs `~/claude-sync/status.sh`. |

`backup`, `restore`, and `status` call the stable scripts under `~/claude-sync/` (present
after setup). `setup` calls the plugin's own bundled `scripts/setup.sh`, because
`~/claude-sync` may not exist yet on a fresh machine.

### Restore is non-destructive

`/claude-sync:restore` only writes to `~/claude-restore` and then prints the exact
`rsync` + `reindex` commands to place files. Review them and run them yourself — nothing
overwrites your live config automatically.

---

## Automatic backups

The `com.alex.claude-backup` LaunchAgent runs `~/claude-sync/backup.sh` at load and every
**7200 seconds (2h)**. Each run takes an incremental snapshot; roughly once per day it also
runs `restic forget --prune` (keep 14 daily / 8 weekly / 12 monthly) and `restic check`.
Output is appended to `~/claude-sync/backup.log`.

The session hooks additionally record your git HEAD at session start and append a
commit/uncommitted-file summary to per-project memory at session end — so the work itself
is captured in the notes that then get backed up.

---

## Maintenance reminders

- **Escrow the restic passphrase.** Losing it makes every snapshot permanently
  unreadable. Keep a copy outside this machine.
- **Rotate R2 tokens periodically.** In the Cloudflare dashboard, mint a new R2 access
  key pair, then re-run `/claude-sync:setup` after deleting
  `~/.config/claude-sync/r2-keys.sh` (setup leaves existing secret files untouched, so you
  must remove the old one first). Revoke the old key afterward.
- **The passphrase and the R2 keys rotate independently.** Rotating R2 keys does NOT
  re-encrypt the repo; the restic passphrase stays the same unless you deliberately run
  `restic key` operations.
- **Verify restores occasionally.** Run `/claude-sync:restore` into `~/claude-restore` and
  spot-check the staged files. A backup you have never restored is a hope, not a backup.

---

## Files

```
~/.config/claude-sync/r2-repo-url   # restic repo URL / R2 bucket endpoint (600)
~/.config/claude-sync/r2-keys.sh    # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (600)
~/.config/claude-sync/restic-pass   # restic passphrase (600)
~/claude-sync/env.sh                # env wiring (patched by setup with your repo URL)
~/claude-sync/backup.sh             # the scheduled backup
~/claude-sync/restore.sh            # staged restore + placement steps
~/claude-sync/status.sh             # read-only health check
~/claude-sync/excludes.txt          # backup exclusions
~/Library/LaunchAgents/com.alex.claude-backup.plist
```
