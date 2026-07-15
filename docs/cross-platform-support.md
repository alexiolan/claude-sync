# Cross-platform support — knowledge & context

> **Purpose of this file.** A durable record of the Windows/cross-platform
> investigation and the design decisions taken so far, so work can resume from a
> fresh terminal (including on the Windows machine) without re-deriving anything.
>
> **Status (2026-07-15):** _investigation + design only. No runtime code has been
> changed yet._ The Windows laptop is greenfield (nothing installed). Next step is
> owner sets up Windows natively, then we resume the sync design from the repo
> terminal on Windows.

---

## TL;DR

- `claude-sync` today is **macOS-only**: bash + launchd + BSD coreutils + Homebrew +
  paths hardcoded to `/Users/alex`. On Windows **as written it does not work**.
- Running two machines (Mac + Windows) against **one shared restic repo**:
  restic guarantees **no data loss / no corruption**, but you get frequent
  **reliability failures** (blocked/aborted runs, broken prune throttle) and,
  conceptually, this is **per-host backup, not two-way sync** — divergent notes can
  be silently clobbered on restore.

### Decisions taken

| Question | Decision | Why |
|----------|----------|-----|
| Windows runtime | **Native Windows** (PowerShell + `restic.exe` + Task Scheduler). **WSL2 rejected** — owner does not want to run a VM on Windows. | Matches a blank Windows laptop without a Linux VM. `restic` ships a native Windows binary; Task Scheduler covers the 2h schedule. |
| Codebase | **Single Python core** for `backup`/`restore`/`status`; thin per-OS adapters for install + scheduler. | Python already required (via `uv` for basic-memory) and runs natively on Windows. Eliminates the whole BSD-vs-GNU-vs-PowerShell bug class. |
| True two-way sync (merge of divergent notes) | **Out of scope for now.** Document that it's per-host backup; `--host` filter stops machines clobbering each other's snapshots. | Real merge is a much larger task. |
| tmux / phone access | **Separate concern, later.** Not part of claude-sync. | It's about how the owner reaches the machine, not about backups. |

---

## Part 1 — Why it does not run on Windows today

Findings from a full audit of `plugins/claude-sync/`, adversarially verified against
restic docs and OS behavior. Severity in brackets.

### Scheduling (macOS-only)
- **[BLOCKER]** The only scheduler is a macOS launchd LaunchAgent
  (`scripts/setup.sh` lines ~182–212: writes `~/Library/LaunchAgents/com.alex.claude-backup.plist`,
  runs `launchctl unload`/`load`). launchd/launchctl/`.plist`/`~/Library/LaunchAgents`
  are all macOS-only. **No Windows equivalent exists anywhere in the code** — the
  "every 2h" backup is never scheduled on Windows.

### Shell + runtime (macOS/bash-only)
- **[BLOCKER]** Every script is `#!/usr/bin/env bash`. Native Windows has no bash.
- **[BLOCKER]** `setup.sh` installs deps via **Homebrew** (`brew`). Homebrew supports
  only macOS/Linux/WSL2, **not native Windows**. On Windows `setup.sh` aborts at the
  **very first step** (Homebrew, `setup.sh` ~lines 26–33): `command -v brew` fails,
  the Homebrew installer runs and exits non-zero, and `set -euo pipefail` kills the
  script there — `restic`/`uv`/`basic-memory` never install. _(Correction to an
  earlier assumption: the abort is at the Homebrew step, not at `launchctl`.)_
- **[HIGH]** `backup.sh` uses BSD **`stat -f %m`** (line ~14). On GNU coreutils
  (Git Bash / MSYS2 / WSL / Linux) this is invalid. Worse than a benign fallback:
  once `.last-prune` exists, `stat -f` prints filesystem text into `last`, then
  `$(( now - last ))` crashes with **`File: unbound variable`** — the crash is caused
  by **`set -u` (nounset)**, not `set -e` (bash recursively evaluates the value `File`
  as an arithmetic identifier). Result: after the first run, **every** `backup.sh`
  run aborts. _(Verified locally: `stat -f %m` and `date -j -f` both fail on GNU
  coreutils 9.4; `stat -c %Y` and `date -d` are the GNU equivalents.)_
- **[HIGH]** `status.sh` uses BSD **`date -j -f`** (line ~23). Invalid on GNU
  coreutils → snapshot "age" is never computed.
- **[MEDIUM]** `jq`, `uv`/`uvx` not present by default on Windows → hooks + MCP +
  basic-memory calls fail. CRLF line endings would also break shebangs.

### Filesystem paths (hardcoded to one macOS home)
- **[HIGH / security]** `scripts/excludes.txt` hardcodes absolute `/Users/alex/...`
  paths. restic matches excludes against real source paths, so on Windows (and on
  **any** non-`alex` account, even on macOS) the patterns **match nothing** →
  `.claude/.credentials.json`, the plugin cache, statsig, todos, and the **live
  basic-memory SQLite DB** all get pulled into the backup. Credentials leaking into
  the backup is the headline risk.
- **[HIGH]** `restore.sh` / `setup.sh` assume the snapshot stores paths under
  `Users/$(id -un)` (`restore.sh` ~lines 33–47) and restore with
  `restic restore latest --target / --include "$HOME/.claude"` (`setup.sh` ~145–151).
  restic reconstructs the **original** absolute path, so cross-user/cross-OS
  placement is wrong.
- **[HIGH]** basic-memory `~/.basic-memory/config.json` stores **per-project absolute
  macOS paths**; restoring on another machine leaves the registry pointing at
  nonexistent dirs → reindex/registration operate on the wrong tree.
- **[LOW]** `env.sh` hardcodes macOS PATH `/opt/homebrew/bin:/usr/local/bin` (line 2).

---

## Part 2 — Concurrent Mac + Windows against one repo

Verified against the restic design docs.

- **No data loss / no corruption.** `restic backup` takes a **non-exclusive** lock, so
  two hosts can back up simultaneously; content-addressed data dedupes safely. R2 is
  strongly consistent (S3 strongly consistent since Dec 2020), so the locking model
  holds. **[SAFE]**
- **Prune is the source of failures. [HIGH]** `restic forget --prune` needs an
  **exclusive** lock (cannot coexist with any other lock) and defaults to
  `--retry-lock=no` (fails immediately). `backup.sh` gates pruning on a **local,
  per-machine** file `~/.config/claude-sync/.last-prune` (20h), so each machine
  prunes independently with **zero cross-host coordination**. Consequences (failures,
  not data loss):
  - a backup that collides with the other machine's prune fails and (`set -e`) aborts
    the run → missed snapshot;
  - both machines prune on their **first** run (`RunAtLoad` + empty `.last-prune`) →
    collision almost guaranteed at start;
  - `touch .last-prune` runs only **after** a successful prune, so a lost lock race
    leaves it un-updated → prune retries on the next 2h tick → the 20h throttle
    collapses into a **2h retry storm**;
  - an interrupted prune/backup leaves a **stale lock** blocking the other machine
    for up to ~30 min (`restic unlock` clears only stale locks >30 min by default).
- **`restore latest` picks the wrong host. [BLOCKER]** With **no `--host`**,
  `restic restore latest` selects the newest snapshot across **all** hosts. On a fresh
  Windows machine, `setup.sh`'s `restore latest --include "$HOME/.claude"` may pull the
  **Mac** snapshot (paths `/Users/alex/...`), which won't match the Windows `$HOME`
  include filter → **silently restores 0 files** (exit 0) and setup continues.
- **Retention is safe. [INFO]** `restic forget` default `--group-by=host,paths`, so the
  14/8/12 policy applies per host — forget from one machine does not delete another
  machine's history.
- **It is not "sync". [BLOCKER-concept]** Per-host snapshots; restore rsyncs a
  point-in-time snapshot over live files **without `--delete`** → last-writer-wins,
  divergent edits silently clobbered, deleted notes resurrect. Session hooks derive
  the project key from the **absolute repo path** (`hooks.json` SessionEnd:
  `sed 's|/|-|g'`), so the same logical project on Mac vs Windows yields **different**
  memory dirs that never reconcile.

---

## Part 3 — Target design (native Windows + Python core)

```
Component            macOS / Linux                 Native Windows
-------------------  ----------------------------  ------------------------------
backup/restore/status  one Python module (shared) — pathlib, no stat/date shell-isms
restic binary          brew / static binary          winget install restic.restic  (restic.exe)
uv + basic-memory      uv (curl installer)           uv (PowerShell installer: irm astral.sh/uv/install.ps1)
secrets                ~/.config/claude-sync (600)   %APPDATA%\claude-sync + icacls ACL
scheduler              launchd .plist                Task Scheduler (Register-ScheduledTask, 2h)
```

Only the **install** and **scheduler** layers are per-OS; everything else is one
Python codebase.

---

## Part 4 — Cross-cutting fixes (do regardless of OS; these also fix macOS/Linux)

1. **`--host "$(hostname)"`** on every `restic restore latest` / `snapshots latest`
   → a machine only ever selects its own snapshots. Kills the "silent empty restore
   from the wrong host" blocker and sidesteps cross-OS absolute-path mismatch.
2. **Generate excludes from `$HOME`** (not `/Users/alex`), or use `**/`-anchored
   patterns → `.credentials.json` + live SQLite DB never leak into the backup on any
   user/OS.
3. **Remove `stat -f %m` / `date -j -f` entirely.** Track prune throttle by writing
   the epoch into `.last-prune` (`date +%s`) and reading the integer back — no `stat`.
   In the Python core, compute age from `restic ... --json`.
4. **Update `.last-prune` even on a lost lock race** (or set `--retry-lock`) → no 2h
   retry storm between machines.
5. **Document sync semantics honestly:** per-host backup, not two-way sync. `--host`
   filter stops mutual snapshot clobbering.

---

## Part 5 — Phasing (when we start coding)

- **Phase 0 — cross-cutting fixes** (Part 4). Fixes current macOS too; lowest risk.
- **Phase 1 — Python core** for backup/restore/status. macOS keeps working; BSD-isms
  disappear as a class.
- **Phase 2 — Windows adapters:** install (winget + `uv`), secrets (`%APPDATA%` +
  `icacls`), scheduler (Task Scheduler `.ps1`).
- **Phase 3 — OS-dispatching setup** + Windows runbook in README.

---

## Part 6 — When resuming on Windows

Report the lay of the land, then we pick up at Phase 0 / the Windows adapter:

- Is Claude Code installed on Windows, and **where is its config** — confirm
  `C:\Users\<you>\.claude`?
- Is a package manager present — **winget** (built into Win 11) or scoop?
- Is **Python / `uv`** available? (`uv` has a first-party PowerShell installer.)
- Is **`restic`** installed (`winget install restic.restic`)?
- How do you want the **secrets** stored on Windows (`%APPDATA%\claude-sync`)?

---

## Appendix — key verification corrections

From adversarial checks against restic docs / OS behavior (things that differ from a
first-glance reading):

- The `backup.sh` arithmetic crash is caused by **`set -u` (nounset)**, not `set -e`.
- On native Windows, `setup.sh` aborts at the **Homebrew** step (step 1), so the
  `.plist` is **never** written — the "launchctl abort" is not the operative failure.
- `restic restore latest` with no `--host` = newest across **all** hosts (confirmed).
- `restic forget` default `--group-by` = **`host,paths`** → per-host retention (safe).
- `restic backup` = non-exclusive lock; `prune` = exclusive lock; only prune removes
  data → concurrency causes availability failures, **not** data loss (confirmed).
- Git Bash's `git rev-parse --show-toplevel` returns `C:/Users/...` (drive-letter,
  forward slashes), not `/c/Users/...` — relevant if Git Bash is ever used.
