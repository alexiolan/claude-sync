#!/usr/bin/env bash
# claude-sync setup — idempotent new-machine bootstrap.
#
# Installs restic, copies the runtime into ~/claude-sync, prompts
# (hidden input) for the R2 keys + restic passphrase, writes the 600 secret files,
# verifies repo access, restores the latest snapshot into ~/.claude and ~/.claude-mem,
# and installs+loads the backup LaunchAgent.
#
# Safe to re-run: every step checks for existing state before acting. Secrets are
# never echoed. This script lives inside the plugin so it works on a machine where
# ~/claude-sync does not exist yet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="$HOME/claude-sync"
CONF_DIR="$HOME/.config/claude-sync"
LABEL="com.alex.claude-backup"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

log()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
log "Checking Homebrew"
if command -v brew >/dev/null 2>&1; then
  note "Homebrew already installed: $(command -v brew)"
else
  note "Installing Homebrew (non-interactive)..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Ensure brew is on PATH for the rest of this run (Apple Silicon vs Intel).
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ---------------------------------------------------------------------------
# 2. restic
# ---------------------------------------------------------------------------
log "Checking restic"
if command -v restic >/dev/null 2>&1; then
  note "restic already installed: $(restic version 2>/dev/null | head -1)"
else
  note "Installing restic via Homebrew..."
  brew install restic
fi

# ---------------------------------------------------------------------------
# 4. Populate ~/claude-sync from the plugin
# ---------------------------------------------------------------------------
log "Setting up $SYNC_DIR"
mkdir -p "$SYNC_DIR"
for f in env.sh backup.sh restore.sh status.sh excludes.txt; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    cp "$SCRIPT_DIR/$f" "$SYNC_DIR/$f"
    note "copied $f"
  fi
done
chmod +x "$SYNC_DIR"/*.sh
note "runtime installed to $SYNC_DIR"

# ---------------------------------------------------------------------------
# 5. Secrets (prompt hidden; write 600 files; never echo values)
# ---------------------------------------------------------------------------
log "Configuring secrets in $CONF_DIR"
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"

if [ -f "$CONF_DIR/r2-keys.sh" ] && [ -f "$CONF_DIR/restic-pass" ] && [ -f "$CONF_DIR/r2-repo-url" ]; then
  note "Secret files already present — leaving them untouched."
  note "(Delete them and re-run if you need to rotate credentials.)"
else
  note "Enter your Cloudflare R2 credentials and restic passphrase."
  note "Input is hidden and never printed back."
  printf '    R2 bucket URL (e.g. s3:https://<account>.r2.cloudflarestorage.com/<bucket>): '
  read -r R2_REPO_URL; echo
  printf '    R2 Access Key ID: '
  read -rs R2_KEY;    echo
  printf '    R2 Secret Access Key: '
  read -rs R2_SECRET; echo
  printf '    restic repository passphrase: '
  read -rs R2_PASS;   echo

  umask 077
  printf '%s' "$R2_REPO_URL" > "$CONF_DIR/r2-repo-url"
  printf 'export AWS_ACCESS_KEY_ID="%s"\nexport AWS_SECRET_ACCESS_KEY="%s"\n' \
    "$R2_KEY" "$R2_SECRET" > "$CONF_DIR/r2-keys.sh"
  printf '%s' "$R2_PASS" > "$CONF_DIR/restic-pass"
  chmod 600 "$CONF_DIR/r2-repo-url" "$CONF_DIR/r2-keys.sh" "$CONF_DIR/restic-pass"
  unset R2_KEY R2_SECRET R2_PASS
  note "Wrote $CONF_DIR/r2-repo-url, r2-keys.sh, and restic-pass (chmod 600)."
fi

# Patch env.sh with the real repo URL from the saved config file.
R2_REPO_URL="$(cat "$CONF_DIR/r2-repo-url")"
sed -i.bak "s|export RESTIC_REPOSITORY=.*|export RESTIC_REPOSITORY=\"${R2_REPO_URL}\"|" \
  "$SYNC_DIR/env.sh" && rm -f "$SYNC_DIR/env.sh.bak"
note "env.sh updated with repo URL."
unset R2_REPO_URL

# env.sh is already copied (step 4); load it now so restic sees the repo + creds.
# shellcheck disable=SC1091
source "$SYNC_DIR/env.sh"

# ---------------------------------------------------------------------------
# 6. Verify repo access (repo already exists — do NOT init)
# ---------------------------------------------------------------------------
log "Verifying access to the restic repository"
if restic snapshots >/dev/null 2>&1; then
  note "Repository reachable. Recent snapshots:"
  restic snapshots --latest 3 || true
else
  echo "ERROR: could not access the restic repository." >&2
  echo "       Check the R2 keys, passphrase, and network, then re-run setup." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 7. Restore latest snapshot into place
# ---------------------------------------------------------------------------
log "Restoring latest snapshot into ~/.claude and ~/.claude-mem"
# restic preserves absolute paths; restoring to '/' lands files at their original homes.
# Restored content is additive (rsync-like overwrite of restored paths only).
restic restore latest --target / \
  --include "$HOME/.claude" \
  --include "$HOME/.claude-mem"
note "Restore complete."

# ---------------------------------------------------------------------------
# 8. claude-mem: promote the snapshot DB (chroma is rebuilt by claude-mem)
# ---------------------------------------------------------------------------
CM="$HOME/.claude-mem"
if [ -f "$CM/claude-mem.snapshot.db" ] && [ ! -f "$CM/claude-mem.db" ]; then
  mv "$CM/claude-mem.snapshot.db" "$CM/claude-mem.db"
  note "Restored claude-mem.db from snapshot."
fi

# ---------------------------------------------------------------------------
# 9. Install + load the LaunchAgent
# ---------------------------------------------------------------------------
log "Installing the backup LaunchAgent ($LABEL)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SYNC_DIR}/backup.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>7200</integer>
    <key>StandardOutPath</key>
    <string>${SYNC_DIR}/backup.log</string>
    <key>StandardErrorPath</key>
    <string>${SYNC_DIR}/backup.log</string>
</dict>
</plist>
PLISTEOF
note "wrote $PLIST"

# Reload cleanly (idempotent): unload if present, then load.
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load  "$PLIST"
note "LaunchAgent loaded (runs at load, then every 7200s)."

log "claude-sync setup complete."
note "Backups run every 2h via launchd and on each load."
note "Check health any time with: /claude-sync:status"
